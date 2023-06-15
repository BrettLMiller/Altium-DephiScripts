{ PanPCB.PrjScr PanPCB.pas PanPCBForm.pas .dfm

Allows Pan & zoom across multiple PcbDocs w.r.t individual board origin.
Any Pcbdoc can be used to move all others.

Set to 1sec refresh.
Click or mouse over the form to start.

Displays matching (to current layer) non-mech layers
Enables and displays (ditto) matching mech layers.
Mechanical layers are ONLY matched by layer number not LayerKinds.

Author BL Miller

202306010  0.10 POC
20230611   0.11 fix tiny mem leak, form to show cursor not BR, failed attempt set current layer.
20230611   0.20 eliminate use WorkSpace & Projects to allow ServDoc.Focus etc
20230611   0.21 match undisplayed layers in other Pcbdocs as they are selected.
20230613   0.22 locate & pan matching selected CMP by designator
20230614   0.23 Three origin modes: board, bottom left & centre of board.
20230615   0.24 support PcbLib by focusing selected FP

tbd:
set same current layer      ; seems not to work with scope & is TV7_layer.
cross highlight CMP with same designator

SetState_CurrentLayer does not exist, & .CurrentLayer appears to fail to set other PcbDocs.
}
const
    bLongTrue     = -1;
    cEnumBoardRef = 'Board Origin|Bottom Left|Centre';

function FocusedPCB(dummy : integer) : boolean;       forward;
function FocusedLib(dummy : integer) : boolean;       forward;
function AllPcbDocs(dummy : integer) : TStringList;   forward;
function AllPcbLibs(dummy : integer) : TStringList;   forward;
function GetViewRect(APCB : IPCB_Board) : TCoordRect; forward;
function CalcOGVR(CPCB : IPCB_Board, OPCB : IPCB_Board, Mode : integer) : TCoordRect; forward;
function IsFlipped(dummy : integer) : boolean;        forward;
function FindLayerObj(ABrd : IPCB_Board, Layer : TLayer) : IPCB_LayerObject; forward;
function ClearBoardSelections(ABrd : IPCB_Board) : boolean; forward;

var
    CurrentPCB     : IPCB_Board;
    CurrentLib     : IPCB_Library;
    CurrentServDoc : IServerDocument;
    slBoardRef     : TStringList;
    iBoardRef      : integer;
    bSameScale     : boolean;
    bCenterCMP     : boolean;

procedure PanPCBs;
begin
    If Client = Nil Then Exit;
    if not Client.StartServer('PCB') then exit;
    If PcbServer = nil then exit;

    FocusedPCB(1);
    FocusedLib(1);
    bSameScale := false;
    bCenterCMP := true;
    iBoardRef := 0;
    slBoardRef := TStringList.Create;
    slBoardRef.Delimiter := '|';
    slBoardRef.StrictDelimiter := true;
    slBoardRef.DelimitedText := cEnumBoardRef;

    PanPCBForm.FormStyle := fsStayOnTop;
    PanPCBForm.Show;
end;

function PanOtherPCBDocs(dummy : integer) : boolean;
var
    PCBSysOpts : IPCB_SystemOptions;
    LayerStack : IPCB_LayerStack_V7;
    ServDoc    : IServerDocument;
    OBrd       : IPCB_Board;
    OLib       : IPCB_Library;
    MechLayer  : IPCB_MechanicalLayer;
    VLSet      : IPCB_LayerSet;
    Prim       : IPCB_Primitive;
    CMP        : IPCB_Component;
    OCMP       : IPCB_Component;
    LibCMP     : IPCB_LibComponent;
    OBO        : TCoordPoint;
    OVR        : TcoordRect;
    DocFPath   : WideString;
    BrdList    : TStringlist;
    PcbLibList : TStringlist;
    I, J       : integer;
    CLayer     : TLayer;
    OLayer     : TLayer;
    CLO        : IPCB_LayerObject;
    CLName     : WideString;
    IsMLayer   : boolean;
    SLayerMode : boolean;
    CBFlipped   : boolean;
    OBFlipped   : boolean;
    bView3D     : boolean;
    CGV    : IPCB_GraphicalView;
begin
    Result := false;

    CMP := nil;
    if CurrentPCB.SelectecObjectCount > 0 then
    begin
        Prim := CurrentPCB.SelectecObject(0);
        if Prim.ObjectID = eComponentObject then CMP := Prim;
        if Prim.InComponent then CMP := Prim.Component;
    end;

    CLayer   := CurrentPCB.GetState_CurrentLayer;
    IsMLayer := LayerUtils.IsMechanicalLayer(CLayer);

    if IsMLayer then
    begin
        LayerStack := CurrentPCB.LayerStack_V7;
        MechLayer := LayerStack.LayerObject_V7[CLayer];
        SLayerMode := MechLayer.DisplayInSingleLayerMode;
    end;

    CGV  := CurrentPCB.GetState_MainGraphicalView;     // TPCBView_DirectX()
    bView3D := CGV.Is3D;

    BrdList := AllPcbDocs(1);
    for I := 0 to (BrdList.Count -1 ) do
    begin
        DocFPath := BrdList.Strings(I);
        ServDoc  := BrdList.Objects(I);
        OBrd     := PCBServer.GetPCBBoardByPath(DocFPath);
// check if not open in PcbServer & ignore.
// should be redundant when using ServerDocument.
        if OBrd = nil then continue;

        If (OBrd.BoardID <> CurrentPCB.BoardID) then
        begin
            ServDoc.Focus;
            OCMP := nil;
            if CMP <> nil then
            begin
                ClearBoardSelections(OBrd);
//                OBrd.SetState_Navigate_HighlightObjectList(eHighlight_Filter,true);
                OCMP := OBrd.GetPcbComponentByRefDes(CMP.Name.Text);
                if OCMP <> nil then
                begin
                    OCMP.Selected := true;
//                    OBrd.AddObjectToHighlightObjectList(OCMP);
//                    OBrd.SetState_Navigate_HighlightObjectList(eHighlight_Thicken,true);
                end;
            end;

            if not IsMLayer then
            if not OBrd.VisibleLayers.Contains(CLayer) then
            begin
                OBrd.VisibleLayers.Include(CLayer);
                CLO := FindLayerObj(CurrentPCB, CLayer);

                OBrd.LayerIsDisplayed(CLayer) := true;
                OBrd.ViewManager_UpdateLayerTabs;
            end;

            if IsMLayer then
            begin
                LayerStack := OBrd.LayerStack_V7;
                MechLayer := LayerStack.LayerObject_V7[CLayer];
                MechLayer.MechanicalLayerEnabled   := true;
                MechLayer.IsDisplayed(OBrd)        := true;
                MechLayer.SetState_DisplayInSingleLayerMode(SLayerMode);
                OBrd.ViewManager_UpdateLayerTabs;
            end;

            OLayer := OBrd.Getstate_CurrentLayer;
            if (OLayer <> CLayer) then
            begin
// this section never executes!!
                OBrd.CurrentLayer := CLayer;
                OBrd.ViewManager_UpdateLayerTabs;
            end;

            OVR := CalcOGVR(CurrentPCB, OBrd, iBoardRef);

            if bCenterCMP and (OCMP <> nil) then
            begin
                OBO := Point(OCMP.X, OCMP.Y);
                OBrd.GraphicalView_ZoomOnRect(OBO.X - RectWidth(OVR)/2, OBO.Y - RectHeight(OVR)/2,
                                              OBO.X + RectWidth(OVR)/2, OBO.Y + RectHeight(OVR)/2);
            end
            else OBrd.GraphicalView_ZoomOnRect(OVR.X1, OVR.Y1, OVR.X2, OVR.Y2);
            OBrd.GraphicalView_ZoomRedraw;

            Result := true;
        end;
    end;

    PCBServer.GetPCBBoardByBoardID(CurrentPCB.BoardID);
    CurrentServDoc.Focus;
    BrdList.Clear;

// PcbLibs open
    If CMP <> nil then
    begin
        PcbLibList := AllPcbLibs(1);
        for I := 0 to (PcbLibList.Count -1 ) do
        begin
            DocFPath := PcbLibList.Strings(I);
            ServDoc  := PcbLibList.Objects(I);
            OLib     := PCBServer.GetPCBLibraryByPath(DocFPath);
            LibCMP := OLib.GetComponentByName(CMP.Pattern);
            OLib.SetState_CurrentComponent(LibCMP);    //must use else Origin & BR all wrong.
//            OLib.RefreshView;
            LibCMP.Board.ViewManager_FullUpdate;
        end;
        PcbLibList.Clear;
    end;
end;

function GetViewCursor(DocKind : WideString) : TCoordPoint;
begin
    Result := TPoint;
    if DocKind = cDocKind_PcbLib then
        Result := Point(CurrentLib.Board.XCursor - CurrentLib.Board.XOrigin, CurrentLib.Board.YCursor - CurrentLib.Board.YOrigin)
    else
        Result := Point(CurrentPCB.XCursor - CurrentPCB.XOrigin, CurrentPCB.YCursor - CurrentPCB.YOrigin);
end;

function GetViewRect(APCB : IPCB_Board) : TCoordRect;
begin
    Result := TRect;
    Result := APCB.GraphicalView_ViewportRect;
    Result := RectToCoordRect(Rect(Result.X1 - APCB.XOrigin, Result.Y2 - APCB.YOrigin,
                                   Result.X2 - APCB.XOrigin, Result.Y1 - APCB.YOrigin) );
end;

// scale new Graph View rect using window sizes, one dimension wins over the other.
function CalcOGVR(CPCB : IPCB_Board, OPCB : IPCB_Board, Mode : integer) : TCoordRect;
var
   GVR : TRect;
   CVR : TCoordRect;
   OBO : TCoordPoint;
   CBO : TCoordRect;
   OBBOR : TCoordRect;
   CBBOR : TCoordRect;
begin
    OBBOR := OPCB.BoardOutline.BoundingRectangle;
    CBBOR := CPCB.BoardOutline.BoundingRectangle;

    Case Mode of
    1 : begin   // bottom left
           OBO := Point(OBBOR.X1, OBBOR.Y1);
           CBO := Point(CBBOR.X1, CBBOR.Y1);
        end;
    2 : begin     // CofMass
           OBO := Point(OBBOR.X1 + RectWidth(OBBOR)/2, OBBOR.Y1 + RectHeight(OBBOR)/2);
           CBO := Point(CBBOR.X1 + RectWidth(CBBOR)/2, CBBOR.Y1 + RectHeight(CBBOR)/2);
        end;
    else begin    // origin
           OBO := Point(OPCB.XOrigin, OPCB.YOrigin);
           CBO := Point(CPCB.XOrigin, CPCB.YOrigin);
         end;
    end;

    GVR := CPCB.GraphicalView_ViewportRect;
    CVR := RectToCoordRect(Rect(GVR.X1 - CBO.X, GVR.Y2 - CBO.Y,
                                GVR.X2 - CBO.X, GVR.Y1 - CBO.Y) );

    Result := RectToCoordRect(Rect(CVR.X1 + OBO.X, CVR.Y2 + OBO.Y,
                                   CVR.X2 + OBO.X, CVR.Y1 + OBO.Y));
end;

function GetViewScale(APCB : IPCB_Board) : extended;
begin
    Result := APCB.Viewport.Scale;
end;

// no good! requires mouse over before status changes.
// but the main menu knows the correct state!
function IsFlipped(dummy : integer) : boolean;
var
    GUIM : IGUIManager;
    state : WideString;
begin
    If Client = Nil Then Exit;
    GUIM := Client.GUIManager;
    GUIM.UpdateInterfaceState;
    Result := false;
    state := GUIM.StatusBar_GetState(1);
    If pos('Flipped',state) <> 0 Then
      Result := true;
end;

function FlipBoard(dummy : integer) : boolean;
begin
    ResetParameters;
    RunProcess('PCB:FlipBoard');
end;

function ClearBoardSelections(ABrd : IPCB_Board) : boolean;
var
    CMP : IPCB_Component;
    I   : integer;
begin
    Result := false;
    ABrd.SelectedObjects_BeginUpdate;
    ABrd.SelectedObjects_Clear;
    ABrd.SelectedObjects_EndUpdate;
    for I := 0 to (ABrd.SelectecObjectCount - 1) do
    begin
        CMP := ABrd.SelectecObject(I);
        CMP.Selected := false;
        Result := true;
    end;
end;

function FindLayerObj(ABrd : IPCB_Board, Layer : TLayer) : IPCB_LayerObject;
var
   LO         : IPCB_LayerObject;
   Lindex     : integer;
begin
    Result := nil; Lindex := 0;
    LO := ABrd.MasterLayerStack.First(eLayerClass_All);
    While (LO <> Nil ) do
    begin
        if LO.V7_LayerID.ID = Layer then
            Result := LO;
        LO := Board.MasterLayerStack.Next(eLayerClass_All, LO);
    end;
end;

function AllPcbDocs(dummy : integer) : TStringList;
var
    SM      : IServerModule;
    Prj     : IProject;
    ServDoc : IServerDocument;
    Doc     : IDocument;
    I, J    : integer;
begin
    Result := TStringlist.Create;
    SM := Client.ServerModuleByName('PCB');
    for I := 0 to (SM.DocumentCount -1) do
    begin
        ServDoc := SM.Documents(I);
        if (ServDoc.Kind = cDocKind_Pcb) then
            Result.AddObject(ServDoc.FileName, ServDoc);
    end;
end;

function AllPcbLibs(dummy : integer) : TStringList;
var
    SM      : IServerModule;
    Prj     : IProject;
    ServDoc : IServerDocument;
    Doc     : IDocument;
    I, J    : integer;
begin
    Result := TStringlist.Create;

    SM := Client.ServerModuleByName('PCB');
    for I := 0 to (SM.DocumentCount -1) do
    begin
        ServDoc := SM.Documents(I);
        if (ServDoc.Kind = cDocKind_PcbLib) then
            Result.AddObject(ServDoc.FileName, ServDoc);
    end;
end;

function FocusedPCB(dummy : integer) : boolean;
var
    SM      : IServerModule;
    ServDoc : IServerDocument;
    APCB    : IPCB_Board;
    I       : integer;
begin
    Result := false;

    SM := Client.ServerModuleByName('PCB');
    for I := 0 to (SM.DocumentCount -1) do
    begin
        ServDoc := SM.Documents(I);
        if (ServDoc.Kind = cDocKind_Pcb) then
        if (ServDoc.IsShown = bLongTrue) then
        begin
            CurrentServDoc := ServDoc;
            APCB := PCBServer.GetCurrentPCBBoard;
            if APCB <> nil then
            if APCB.Filename = ServDoc.FileName then
            begin
                CurrentPCB := APCB;
                Result := true;
            end;
        end;
    end;
end;

function FocusedLib(dummy : integer) : boolean;
var
    SM      : IServerModule;
    ServDoc : IServerDocument;
    APCB    : IPCB_Library;
    I       : integer;
begin
    Result := false;

    SM := Client.ServerModuleByName('PCB');
    for I := 0 to (SM.DocumentCount -1) do
    begin
        ServDoc := SM.Documents(I);
        if (ServDoc.Kind = cDocKind_PcbLib) then
        if (ServDoc.IsShown = bLongTrue) then
        begin
            CurrentServDoc := ServDoc;
            APCB := PCBServer.GetCurrentPCBLibrary;
            if APCB <> nil then
            if APCB.Board.Filename = ServDoc.FileName then
            begin
                CurrentLib := APCB;
                Result := true;
            end;
        end;
    end;
end;

