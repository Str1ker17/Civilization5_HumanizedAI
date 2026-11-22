include( "InstanceManager" );
include( "FLuaVector" );

local g_data = Modding.OpenUserData( "HumanizedAI", 1 );
local g_dots = InstanceManager:new( "Dot", "Anchor", Controls.DotStore );
local g_markers = InstanceManager:new( "Marker", "Anchor", Controls.MarkerStore );
local g_prev = {};
local g_moves = {};
local g_selected = nil;
local g_pausedTurn = -1;
local g_refresh = false;
local g_pickX, g_pickY = nil, nil;
local g_pickMarker = InstanceManager:new( "Marker", "Anchor", Controls.MarkerStore );
local g_attacks = {};
local g_upgrades = {};
local g_founded = {};
local g_coach = tonumber( g_data.GetValue( "Coach" ) ) or -1;
local g_fixes = {};
local g_fixDots = InstanceManager:new( "Dot", "Anchor", Controls.DotStore );
local g_fixMarkers = InstanceManager:new( "Marker", "Anchor", Controls.MarkerStore );
local g_turnStartSave = -1;
local g_replayPending = g_coach >= 0 and tonumber( g_data.GetValue( "CoachReplay" ) ) == 1;
local g_replayTurn = -1;
local g_lookedAt = false;
local g_bigDots = InstanceManager:new( "BigDot", "Anchor", Controls.DotStore );
local g_notes = tonumber( g_data.GetValue( "SuperviseNotes" ) ) or 0;
local g_queueLines = InstanceManager:new( "QueueLine", "Button", Controls.QueueStack );
local g_queueShown = false;
local g_selectedQueue = nil;

local function Log( text )
	print( "HumanizedSupervise: " .. text );
end

local function CivName( playerID )
	return Locale.ConvertTextKey( Players[ playerID ]:GetCivilizationShortDescriptionKey() );
end

local function Snapshot()
	local snap = {};
	for playerID = 0, GameDefines.MAX_PLAYERS - 1 do
		local player = Players[ playerID ];
		if player and player:IsAlive() and not player:IsMinorCiv() and playerID ~= Game.GetActivePlayer() then
			local units = {};
			for unit in player:Units() do
				if unit:GetX() >= 0 and unit:GetY() >= 0 then
					units[ unit:GetID() ] = { x = unit:GetX(), y = unit:GetY(), hp = unit:GetCurrHitPoints(),
						combat = unit:IsCombatUnit(), inCity = unit:GetPlot():IsCity(), found = unit:IsFound(),
						name = Locale.ConvertTextKey( GameInfo.Units[ unit:GetUnitType() ].Description ) };
				end
			end
			snap[ playerID ] = units;
		end
	end
	return snap;
end

local function Diff( old, new )
	local moves = {};
	for playerID, units in pairs( new ) do
		local before = old[ playerID ] or {};
		local replaced = {};
		for unitID, u in pairs( units ) do
			local b = before[ unitID ];
			local oldID = g_upgrades[ playerID .. ":" .. unitID ];
			if b == nil and oldID ~= nil then
				replaced[ oldID ] = true;
				local o = before[ oldID ] or u;
				local name = u.name;
				if o ~= u then
					name = o.name .. " -> " .. u.name;
				end
				table.insert( moves, { player = playerID, unit = unitID, name = name, fx = o.x, fy = o.y, tx = u.x, ty = u.y, hp0 = o.hp, hp1 = u.hp, kind = "upgrade" } );
			elseif b == nil then
				table.insert( moves, { player = playerID, unit = unitID, name = u.name, fx = u.x, fy = u.y, tx = u.x, ty = u.y, hp0 = u.hp, hp1 = u.hp, kind = "new" } );
			elseif b.x ~= u.x or b.y ~= u.y then
				table.insert( moves, { player = playerID, unit = unitID, name = u.name, fx = b.x, fy = b.y, tx = u.x, ty = u.y, hp0 = b.hp, hp1 = u.hp, kind = "move" } );
			elseif ( u.combat and not u.inCity ) or playerID == g_coach then
				table.insert( moves, { player = playerID, unit = unitID, name = u.name, fx = b.x, fy = b.y, tx = u.x, ty = u.y, hp0 = b.hp, hp1 = u.hp, kind = "idle" } );
			end
		end
		for unitID, b in pairs( before ) do
			if units[ unitID ] == nil and not replaced[ unitID ] then
				local city = nil;
				if b.found then
					for i, c in ipairs( g_founded ) do
						if c.player == playerID and ( city == nil or Map.PlotDistance( b.x, b.y, c.x, c.y ) < Map.PlotDistance( b.x, b.y, g_founded[ city ].x, g_founded[ city ].y ) ) then
							city = i;
						end
					end
				end
				if city ~= nil then
					local c = table.remove( g_founded, city );
					table.insert( moves, { player = playerID, unit = unitID, name = b.name, fx = b.x, fy = b.y, tx = c.x, ty = c.y, hp0 = b.hp, hp1 = b.hp, kind = "founded" } );
				else
					table.insert( moves, { player = playerID, unit = unitID, name = b.name, fx = b.x, fy = b.y, tx = b.x, ty = b.y, hp0 = b.hp, hp1 = 0, kind = "lost" } );
				end
			end
		end
	end
	return moves;
end

local function Describe( m )
	local what = { move = "ход", new = "новый", lost = "потерян", idle = "стоял", attack = "атака", upgrade = "улучшен", founded = "основал город" };
	local hp = "";
	if m.hp0 and m.hp1 and m.hp0 ~= m.hp1 then
		hp = string.format( ", HP %d -> %d", m.hp0, m.hp1 );
	end
	return string.format( "%s: %s (id %d) %s %d,%d -> %d,%d%s", CivName( m.player ), m.name, m.unit, what[ m.kind ], m.fx, m.fy, m.tx, m.ty, hp );
end

local function ClearPick()
	g_pickX, g_pickY = nil, nil;
	g_pickMarker:ResetInstances();
end

local function Select( m )
	ClearPick();
	g_selected = m;
	g_selectedQueue = nil;
	Controls.MoveLabel:SetText( "Выбрано: " .. Describe( m ) );
	Controls.Note:TakeFocus();
end

local function SelectQueue( q )
	ClearPick();
	g_selectedQueue = q;
	g_selected = nil;
	Controls.MoveLabel:SetText( "Выбрано: " .. q.text );
	Controls.Note:TakeFocus();
end

local function DrawLine( manager, fx, fy, tx, ty, color )
	local a = HexToWorld( ToHexFromGrid( Vector2( fx, fy ) ) );
	local b = HexToWorld( ToHexFromGrid( Vector2( tx, ty ) ) );
	local steps = 3 * math.max( Map.PlotDistance( fx, fy, tx, ty ), 1 );
	for k = 0, steps - 1 do
		local dot = manager:GetInstance();
		dot.Anchor:SetWorldPositionVal( a.x + ( b.x - a.x ) * k / steps, a.y + ( b.y - a.y ) * k / steps, a.z + ( b.z - a.z ) * k / steps );
		dot.Box:SetColor( color );
	end
end

local function DrawFixes()
	g_fixDots:ResetInstances();
	g_fixMarkers:ResetInstances();
	for _, f in pairs( g_fixes ) do
		DrawLine( g_fixDots, f.fx, f.fy, f.x, f.y, Vector4( 0.1, 1, 0.1, 1 ) );
		local marker = g_fixMarkers:GetInstance();
		marker.Anchor:SetHexPosition( f.x, f.y );
		marker.Box:SetColor( Vector4( 0.1, 1, 0.1, 1 ) );
		marker.Mark:SetText( "v" );
		marker.Button:SetToolTipString( string.format( "Поправка: %s -> %d,%d", f.name, f.x, f.y ) );
	end
end

local function AddFix( m, x, y )
	g_fixes[ m.unit ] = { unit = m.unit, name = m.name, fx = m.fx, fy = m.fy, ax = m.tx, ay = m.ty, x = x, y = y };
	DrawFixes();
	Controls.MoveLabel:SetText( string.format( "Поправка: %s пойдёт на %d,%d вместо %d,%d. Напиши почему и нажми «Плохой ход», потом «Переиграть ход».", m.name, x, y, m.tx, m.ty ) );
	Controls.Note:TakeFocus();
	Log( string.format( "fix unit=%d to=%d,%d", m.unit, x, y ) );
end

local function SelectPlot( x, y )
	ClearPick();
	g_selected = nil;
	g_selectedQueue = nil;
	g_pickX, g_pickY = x, y;
	local marker = g_pickMarker:GetInstance();
	marker.Anchor:SetHexPosition( x, y );
	marker.Box:SetColor( Vector4( 1, 1, 0, 1 ) );
	marker.Mark:SetText( "?" );
	marker.Button:SetToolTipString( string.format( "Клетка %d,%d", x, y ) );
	Controls.MoveLabel:SetText( string.format( "Выбрана клетка %d,%d", x, y ) );
	Controls.Note:TakeFocus();
	Log( string.format( "picked plot=%d,%d", x, y ) );
end

local function AddQueueLine( q )
	local line = g_queueLines:GetInstance();
	line.Text:SetText( q.text );
	line.Button:RegisterCallback( Mouse.eLClick, function() SelectQueue( q ); end );
end

local function RefreshQueues()
	g_queueLines:ResetInstances();
	for playerID = 0, GameDefines.MAX_MAJOR_CIVS - 1 do
		local player = Players[ playerID ];
		if player and player:IsAlive() and not player:IsMinorCiv() and playerID ~= Game.GetActivePlayer() then
			local tech = player:GetCurrentResearch();
			local techName = "ничего";
			local techTurns = "";
			if tech ~= nil and tech >= 0 and GameInfo.Technologies[ tech ] then
				techName = Locale.ConvertTextKey( GameInfo.Technologies[ tech ].Description );
				techTurns = string.format( ", %d ход.", player:GetResearchTurnsLeft( tech, true ) );
			end
			AddQueueLine( { kind = "research", player = playerID, city = "", item = techName,
				text = string.format( "%s: изучает %s%s", CivName( playerID ), techName, techTurns ) } );
			for city in player:Cities() do
				local cityName = Locale.ConvertTextKey( city:GetNameKey() );
				local key = city:GetProductionNameKey();
				local item = "ничего";
				local turns = "";
				if key ~= nil and key ~= "" then
					item = Locale.ConvertTextKey( key );
					turns = string.format( ", %d ход.", city:GetProductionTurnsLeft() );
				end
				AddQueueLine( { kind = "production", player = playerID, city = cityName, item = item,
					text = string.format( "      %s (%d жит.): строит %s%s", cityName, city:GetPopulation(), item, turns ) } );
			end
		end
	end
	Controls.QueueStack:CalculateSize();
	Controls.QueueStack:ReprocessAnchoring();
	Controls.QueueScroll:CalculateInternalSize();
end

local function OnQueue()
	g_queueShown = not g_queueShown;
	Controls.QueuePanel:SetHide( not g_queueShown );
	if g_queueShown then
		RefreshQueues();
	end
end

local function Draw()
	g_dots:ResetInstances();
	g_bigDots:ResetInstances();
	g_markers:ResetInstances();
	local stacked = {};
	for _, m in ipairs( g_moves ) do
		local _, color = Players[ m.player ]:GetPlayerColors();
		local dotColor = color;
		if m.kind == "attack" then
			dotColor = Vector4( 1, 0.1, 0.1, 1 );
		end
		if ( m.kind == "move" or m.kind == "attack" ) and Map.PlotDistance( m.fx, m.fy, m.tx, m.ty ) <= 8 then
			local a = HexToWorld( ToHexFromGrid( Vector2( m.fx, m.fy ) ) );
			local b = HexToWorld( ToHexFromGrid( Vector2( m.tx, m.ty ) ) );
			local steps = 3 * Map.PlotDistance( m.fx, m.fy, m.tx, m.ty );
			local dots = g_dots;
			if m.player == g_coach then
				dots = g_bigDots;
			end
			for k = 0, steps - 1 do
				local dot = dots:GetInstance();
				dot.Anchor:SetWorldPositionVal( a.x + ( b.x - a.x ) * k / steps, a.y + ( b.y - a.y ) * k / steps, a.z + ( b.z - a.z ) * k / steps );
				dot.Box:SetColor( dotColor );
			end
		end
		local key = m.tx .. "," .. m.ty;
		stacked[ key ] = ( stacked[ key ] or 0 ) + 1;
		local marker = g_markers:GetInstance();
		marker.Anchor:SetHexPosition( m.tx, m.ty );
		marker.Button:SetOffsetVal( ( stacked[ key ] - 1 ) * 22, 0 );
		marker.Box:SetColor( color );
		marker.Mark:SetText( ( { move = "", new = "+", lost = "x", idle = "=", attack = "!", upgrade = "^", founded = "#" } )[ m.kind ] );
		marker.Button:SetToolTipString( Describe( m ) );
		marker.Button:RegisterCallback( Mouse.eLClick, function() Select( m ); end );
	end
end

local function Refresh()
	local snap = Snapshot();
	g_moves = Diff( g_prev, snap );
	for _, a in ipairs( g_attacks ) do
		table.insert( g_moves, a );
	end
	g_attacks = {};
	g_upgrades = {};
	g_founded = {};
	g_prev = snap;
	g_selected = nil;
	g_selectedQueue = nil;
	ClearPick();
	Draw();
	if g_queueShown then
		RefreshQueues();
	end
	Controls.TurnLabel:SetText( string.format( "Ход %d, пауза. Изменений: %d. Записано заметок: %d", Game.GetGameTurn(), #g_moves, g_notes ) );
	Controls.MoveLabel:SetText( "Клик по маркеру выбирает ход, правый клик по карте выбирает клетку. Маркеры: + новый, x потерян, = стоял, ! атака (красный пунктир), ^ улучшен, # основал город." );
	local kinds = {};
	for _, m in ipairs( g_moves ) do
		kinds[ m.kind ] = ( kinds[ m.kind ] or 0 ) + 1;
	end
	Log( string.format( "paused turn=%d changes=%d upgrade=%d founded=%d lost=%d", Game.GetGameTurn(), #g_moves, kinds.upgrade or 0, kinds.founded or 0, kinds.lost or 0 ) );
	if g_coach >= 0 then
		g_fixes = {};
		DrawFixes();
		if not g_lookedAt and Players[ g_coach ] and Players[ g_coach ]:GetCapitalCity() then
			g_lookedAt = true;
			UI.LookAt( Players[ g_coach ]:GetCapitalCity():Plot(), 0 );
		end
		g_replayTurn = g_turnStartSave;
		UI.SaveGame( "coach-" .. Game.GetGameTurn() );
		g_turnStartSave = Game.GetGameTurn();
		Controls.ReplayButton:SetHide( g_replayTurn < 0 );
		Log( string.format( "saved coach-%d replay=%d", Game.GetGameTurn(), g_replayTurn ) );
	end
end

local function OnReplay()
	if g_replayTurn < 0 then
		return;
	end
	local name = "coach-" .. g_replayTurn;
	local files = {};
	UI.SaveFileList( files, GameTypes.GAME_SINGLE_PLAYER, false, true );
	local path = nil;
	for _, f in pairs( files ) do
		if string.match( f, "([^\\/]+)%.[Cc]iv5[Ss]ave$" ) == name then
			path = f;
		end
	end
	if path == nil then
		Controls.MoveLabel:SetText( "Не нашёл сохранение " .. name );
		Log( "replay no save " .. name );
		return;
	end
	local list = {};
	for _, f in pairs( g_fixes ) do
		table.insert( list, string.format( "%d:%d:%d", f.unit, f.x, f.y ) );
	end
	g_data.SetValue( "CoachFixes", table.concat( list, ";" ) );
	g_data.SetValue( "CoachReplayTurn", g_replayTurn );
	g_data.SetValue( "CoachReplay", 1 );
	Log( string.format( "replay turn=%d fixes=%d file=%s", g_replayTurn, #list, path ) );
	Controls.TurnLabel:SetText( "Загрузка начала хода " .. g_replayTurn .. "..." );
	Events.PlayerChoseToLoadGame( path );
end

local function ApplyReplay()
	g_data.SetValue( "CoachReplay", 0 );
	local turn = Game.GetGameTurn();
	g_turnStartSave = turn;
	g_prev = Snapshot();
	local applied = 0;
	local player = Players[ g_coach ];
	if player and tonumber( g_data.GetValue( "CoachReplayTurn" ) ) == turn then
		for id, x, y in string.gmatch( g_data.GetValue( "CoachFixes" ) or "", "(%d+):(%d+):(%d+)" ) do
			local unit = player:GetUnitByID( tonumber( id ) );
			if unit then
				local fx, fy = unit:GetX(), unit:GetY();
				if unit:IsRanged() and unit:CanRangeStrikeAt( tonumber( x ), tonumber( y ) ) then
					unit:PushMission( MissionTypes.MISSION_RANGE_ATTACK, tonumber( x ), tonumber( y ) );
				else
					unit:PushMission( MissionTypes.MISSION_MOVE_TO, tonumber( x ), tonumber( y ) );
				end
				unit:FinishMoves();
				applied = applied + 1;
				Log( string.format( "fix applied unit=%s from=%d,%d to=%s,%s now=%d,%d", id, fx, fy, x, y, unit:GetX(), unit:GetY() ) );
			end
		end
	end
	Log( string.format( "replay loaded turn=%d applied=%d", turn, applied ) );
	Controls.TurnLabel:SetText( "Переигровка хода " .. turn .. ", ИИ ходит..." );
	Game.SetPausePlayer( -1 );
end

local function OnBad()
	local note = Controls.Note:GetText() or "";
	local line;
	if g_selectedQueue then
		local q = g_selectedQueue;
		line = string.format( "bad turn=%d player=%d civ=%s kind=%s city=%s item=%s note=%s",
			Game.GetGameTurn(), q.player, CivName( q.player ), q.kind, q.city, q.item, note );
	elseif g_selected then
		local m = g_selected;
		local fix = "";
		if m.player == g_coach and g_fixes[ m.unit ] then
			fix = string.format( " fix=%d,%d", g_fixes[ m.unit ].x, g_fixes[ m.unit ].y );
		end
		line = string.format( "bad turn=%d player=%d civ=%s unit=%d name=%s kind=%s from=%d,%d to=%d,%d%s note=%s",
			Game.GetGameTurn(), m.player, CivName( m.player ), m.unit, m.name, m.kind, m.fx, m.fy, m.tx, m.ty, fix, note );
	elseif g_pickX ~= nil then
		local plot = Map.GetPlot( g_pickX, g_pickY );
		local owner = "";
		local city = "";
		if plot:GetOwner() >= 0 then
			owner = CivName( plot:GetOwner() );
		end
		if plot:IsCity() then
			city = Locale.ConvertTextKey( plot:GetPlotCity():GetNameKey() );
		end
		line = string.format( "bad turn=%d plot=%d,%d owner=%s city=%s note=%s", Game.GetGameTurn(), g_pickX, g_pickY, owner, city, note );
	else
		Controls.MoveLabel:SetText( "Сначала выбери маркер хода, строку очереди или клетку правым кликом. Текст заметки сохранён в поле." );
		return;
	end
	g_notes = g_notes + 1;
	g_data.SetValue( "SuperviseNote" .. g_notes, line );
	g_data.SetValue( "SuperviseNotes", g_notes );
	Log( line );
	Controls.Note:SetText( "" );
	Controls.TurnLabel:SetText( string.format( "Ход %d, пауза. Изменений: %d. Записано заметок: %d", Game.GetGameTurn(), #g_moves, g_notes ) );
	Controls.MoveLabel:SetText( "Записано: " .. line );
end

local function OnNext()
	g_dots:ResetInstances();
	g_bigDots:ResetInstances();
	g_markers:ResetInstances();
	g_fixes = {};
	DrawFixes();
	ClearPick();
	g_selected = nil;
	g_selectedQueue = nil;
	Controls.TurnLabel:SetText( "ИИ ходит..." );
	Controls.MoveLabel:SetText( "" );
	Game.SetPausePlayer( -1 );
end

Controls.BadLabel:SetText( "Плохой ход" );
Controls.NextLabel:SetText( "Следующий ход" );
Controls.QueueLabel:SetText( "Очереди" );
Controls.BadButton:RegisterCallback( Mouse.eLClick, OnBad );
Controls.NextButton:RegisterCallback( Mouse.eLClick, OnNext );
Controls.QueueButton:RegisterCallback( Mouse.eLClick, OnQueue );
Controls.ReplayLabel:SetText( "Переиграть ход" );
Controls.ReplayButton:RegisterCallback( Mouse.eLClick, OnReplay );

ContextPtr:SetInputHandler( function( uiMsg, wParam, lParam )
	if uiMsg == MouseEvents.RButtonUp and Game.IsPaused() then
		local x, y = UI.GetMouseOverHex();
		if x ~= nil and Map.GetPlot( x, y ) ~= nil then
			if g_selected and g_selected.player == g_coach then
				AddFix( g_selected, x, y );
			else
				SelectPlot( x, y );
			end
		end
	end
	return false;
end );

GameEvents.UnitUpgraded.Add( function( playerID, oldID, newID, goody )
	g_upgrades[ playerID .. ":" .. newID ] = oldID;
end );

GameEvents.PlayerCityFounded.Add( function( playerID, x, y )
	table.insert( g_founded, { player = playerID, x = x, y = y } );
end );

GameEvents.HumanizedCombat.Add( function( playerID, unitID, fromX, fromY, toX, toY )
	local player = Players[ playerID ];
	if player == nil or player:IsMinorCiv() then
		return;
	end
	local name = "город";
	local unit = unitID >= 0 and player:GetUnitByID( unitID );
	if unit then
		name = Locale.ConvertTextKey( GameInfo.Units[ unit:GetUnitType() ].Description );
	end
	table.insert( g_attacks, { player = playerID, unit = unitID, name = name, fx = fromX, fy = fromY, tx = toX, ty = toY, kind = "attack" } );
end );

GameEvents.PlayerDoTurn.Add( function( playerID )
	if g_coach >= 0 and playerID ~= g_coach and Players[ g_coach ] and Players[ g_coach ]:IsAlive() then
		return;
	end
	if Game.GetGameTurn() ~= g_pausedTurn then
		g_pausedTurn = Game.GetGameTurn();
		Game.SetPausePlayer( Game.GetActivePlayer() );
		g_refresh = true;
	end
end );

ContextPtr:SetUpdate( function()
	if g_replayPending and g_data.GetValue( "Status" ) == "running" then
		g_replayPending = false;
		ApplyReplay();
	end
	if g_refresh then
		g_refresh = false;
		Refresh();
	end
end );

g_prev = Snapshot();
Controls.TurnLabel:SetText( "ИИ ходит..." );
Controls.MoveLabel:SetText( "" );
Log( "loaded turn=" .. Game.GetGameTurn() );
