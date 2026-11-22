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
local g_hoverX, g_hoverY = -1, -1;
local g_attacks = {};
local g_notes = tonumber( g_data.GetValue( "SuperviseNotes" ) ) or 0;

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
						combat = unit:IsCombatUnit(), inCity = unit:GetPlot():IsCity(),
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
		for unitID, u in pairs( units ) do
			local b = before[ unitID ];
			if b == nil then
				table.insert( moves, { player = playerID, unit = unitID, name = u.name, fx = u.x, fy = u.y, tx = u.x, ty = u.y, hp0 = u.hp, hp1 = u.hp, kind = "new" } );
			elseif b.x ~= u.x or b.y ~= u.y then
				table.insert( moves, { player = playerID, unit = unitID, name = u.name, fx = b.x, fy = b.y, tx = u.x, ty = u.y, hp0 = b.hp, hp1 = u.hp, kind = "move" } );
			elseif u.combat and not u.inCity then
				table.insert( moves, { player = playerID, unit = unitID, name = u.name, fx = b.x, fy = b.y, tx = u.x, ty = u.y, hp0 = b.hp, hp1 = u.hp, kind = "idle" } );
			end
		end
		for unitID, b in pairs( before ) do
			if units[ unitID ] == nil then
				table.insert( moves, { player = playerID, unit = unitID, name = b.name, fx = b.x, fy = b.y, tx = b.x, ty = b.y, hp0 = b.hp, hp1 = 0, kind = "lost" } );
			end
		end
	end
	return moves;
end

local function Describe( m )
	local what = { move = "ход", new = "новый", lost = "потерян", idle = "стоял", attack = "атака" };
	local hp = "";
	if m.hp0 and m.hp1 and m.hp0 ~= m.hp1 then
		hp = string.format( ", HP %d -> %d", m.hp0, m.hp1 );
	end
	return string.format( "%s: %s (id %d) %s %d,%d -> %d,%d%s", CivName( m.player ), m.name, m.unit, what[ m.kind ], m.fx, m.fy, m.tx, m.ty, hp );
end

local function Select( m )
	g_selected = m;
	Controls.MoveLabel:SetText( "Выбрано: " .. Describe( m ) );
	Controls.Note:TakeFocus();
end

local function Draw()
	g_dots:ResetInstances();
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
			for k = 0, steps - 1 do
				local dot = g_dots:GetInstance();
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
		marker.Mark:SetText( ( { move = "", new = "+", lost = "x", idle = "=", attack = "!" } )[ m.kind ] );
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
	g_prev = snap;
	g_selected = nil;
	Draw();
	Controls.TurnLabel:SetText( string.format( "Ход %d, пауза. Изменений: %d. Записано заметок: %d", Game.GetGameTurn(), #g_moves, g_notes ) );
	Controls.MoveLabel:SetText( "Клик по маркеру выбирает ход. Без выбора заметка относится к клетке под курсором. Маркеры: + новый, x потерян, = стоял, ! атака (красный пунктир)." );
	Log( string.format( "paused turn=%d changes=%d", Game.GetGameTurn(), #g_moves ) );
end

local function OnBad()
	local note = Controls.Note:GetText() or "";
	local line;
	if g_selected then
		local m = g_selected;
		line = string.format( "bad turn=%d player=%d civ=%s unit=%d name=%s kind=%s from=%d,%d to=%d,%d note=%s",
			Game.GetGameTurn(), m.player, CivName( m.player ), m.unit, m.name, m.kind, m.fx, m.fy, m.tx, m.ty, note );
	else
		line = string.format( "bad turn=%d plot=%d,%d note=%s", Game.GetGameTurn(), g_hoverX, g_hoverY, note );
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
	g_markers:ResetInstances();
	g_selected = nil;
	Controls.TurnLabel:SetText( "ИИ ходит..." );
	Controls.MoveLabel:SetText( "" );
	Game.SetPausePlayer( -1 );
end

Controls.BadLabel:SetText( "Плохой ход" );
Controls.NextLabel:SetText( "Следующий ход" );
Controls.BadButton:RegisterCallback( Mouse.eLClick, OnBad );
Controls.NextButton:RegisterCallback( Mouse.eLClick, OnNext );

Events.SerialEventMouseOverHex.Add( function( hexX, hexY )
	g_hoverX, g_hoverY = hexX, hexY;
	if g_selected == nil and Game.IsPaused() then
		Controls.MoveLabel:SetText( string.format( "Заметка без выбора пойдёт к клетке %d,%d", hexX, hexY ) );
	end
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
	if Game.GetGameTurn() ~= g_pausedTurn then
		g_pausedTurn = Game.GetGameTurn();
		Game.SetPausePlayer( Game.GetActivePlayer() );
		g_refresh = true;
	end
end );

ContextPtr:SetUpdate( function()
	if g_refresh then
		g_refresh = false;
		Refresh();
	end
end );

g_prev = Snapshot();
Controls.TurnLabel:SetText( "ИИ ходит..." );
Controls.MoveLabel:SetText( "" );
Log( "loaded turn=" .. Game.GetGameTurn() );
