local g_chatData = Modding.OpenUserData( "HumanizedAI", 1 );

local function ChatLog( text )
	print( "HumanizedChat: " .. text );
end

local function PlayerName( playerID )
	local player = Players[ playerID ];
	if player == nil then
		return tostring( playerID );
	end
	return Locale.ConvertTextKey( player:GetCivilizationShortDescriptionKey() );
end

function HumanizedChatPlotTag()
	local x, y = UI.GetMouseOverHex();
	local plot = x ~= nil and Map.GetPlot( x, y );
	if not plot then
		return nil;
	end
	local team = Game.GetActiveTeam();
	local tag = string.format( "%d,%d", x, y );
	if plot:IsCity() and plot:IsRevealed( team, false ) then
		local city = plot:GetPlotCity();
		tag = tag .. " " .. Locale.ConvertTextKey( city:GetNameKey() ) .. ", " .. PlayerName( city:GetOwner() );
	elseif plot:IsVisible( team, false ) then
		for i = 0, plot:GetNumUnits() - 1 do
			local unit = plot:GetUnit( i );
			if unit then
				tag = tag .. " " .. PlayerName( unit:GetOwner() ) .. " " .. Locale.ConvertTextKey( GameInfo.Units[ unit:GetUnitType() ].Description );
				break;
			end
		end
	end
	ChatLog( "tag " .. tag );
	return "(" .. tag .. ") ";
end

local function Record( prefix, countKey, turn, fromPlayer, text )
	local n = ( tonumber( g_chatData.GetValue( countKey ) ) or 0 ) + 1;
	local line = string.format( "turn=%d from=%s text=%s", turn, PlayerName( fromPlayer ), text );
	g_chatData.SetValue( prefix .. n, line );
	g_chatData.SetValue( countKey, n );
	return line;
end

function HumanizedChatDumpHistory()
	g_chatData.SetValue( "ChatHists", 0 );
	local count = 0;
	for _, message in ipairs( Game.GetReplayMessages() ) do
		if message.Type == 7 then
			count = count + 1;
			ChatLog( "history " .. Record( "ChatHist", "ChatHists", message.Turn or -1, message.Player, message.Text or "" ) );
		end
	end
	ChatLog( string.format( "history dumped %d messages at turn %d", count, Game.GetGameTurn() ) );
end

Events.GameMessageChat.Add( function( fromPlayer, toPlayer, text, eTargetType )
	ChatLog( "live " .. Record( "ChatNote", "ChatNotes", Game.GetGameTurn(), fromPlayer, text or "" ) );
end );
