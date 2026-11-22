local g_autoplayData = Modding.OpenUserData( "HumanizedAI", 1 );

local function AutoplayGet( name )
	return g_autoplayData.GetValue( name );
end

local function AutoplaySet( name, value )
	g_autoplayData.SetValue( name, value );
end

local function AutoplayTurns()
	return tonumber( AutoplayGet( "AutoplayTurns" ) ) or 0;
end

local function AutoplayLog( text )
	print( "HumanizedAutoplay: " .. text );
end

local function AutoplaySetupAndStart()
	local loadFile = AutoplayGet( "LoadFile" );
	if loadFile and loadFile ~= "" then
		AutoplayLog( "load " .. loadFile );
		AutoplaySet( "Status", "launching" );
		Events.PlayerChoseToLoadGame( loadFile );
		return;
	end
	PreGame.SetGameType( GameTypes.GAME_SINGLE_PLAYER );
	PreGame.ResetSlots();
	PreGame.ResetGameOptions();
	PreGame.ResetMapOptions();
	PreGame.SetLoadWBScenario( false );
	for name, value in string.gmatch( AutoplayGet( "GameOptions" ) or "", "([%w_]+)=(%d)" ) do
		PreGame.SetGameOption( name, value == "1" );
	end

	local mapScript = AutoplayGet( "MapScript" );
	if mapScript and mapScript ~= "" then
		PreGame.SetRandomMapScript( false );
		PreGame.SetMapScript( mapScript );
	end
	local world = GameInfo.Worlds[ AutoplayGet( "WorldSize" ) or "" ];
	if world then
		PreGame.SetRandomWorldSize( false );
		PreGame.SetWorldSize( world.ID );
	end
	local speed = GameInfo.GameSpeeds[ AutoplayGet( "GameSpeed" ) or "" ];
	if speed then
		PreGame.SetGameSpeed( speed.ID );
	end
	local handicap = GameInfo.HandicapInfos[ AutoplayGet( "Handicap" ) or "" ];
	if handicap then
		PreGame.SetHandicap( 0, handicap.ID );
	end
	PreGame.SetQuickCombat( true );
	PreGame.SetQuickMovement( true );

	PreGame.SetSlotStatus( 0, SlotStatus.SS_OBSERVER );
	local slot = 1;
	for civType in string.gmatch( AutoplayGet( "Civs" ) or "", "[^,%s]+" ) do
		local civ = GameInfo.Civilizations[ civType ];
		if civ then
			PreGame.SetSlotStatus( slot, SlotStatus.SS_COMPUTER );
			PreGame.SetCivilization( slot, civ.ID );
			PreGame.SetTeam( slot, slot );
			slot = slot + 1;
		else
			AutoplayLog( "unknown civilization " .. civType );
		end
	end
	for i = slot, ( GameDefines.MAX_MAJOR_CIVS or 22 ) - 1 do
		PreGame.SetSlotStatus( i, SlotStatus.SS_CLOSED );
	end
	local minors = tonumber( AutoplayGet( "MinorCivs" ) );
	if minors then
		PreGame.SetNumMinorCivs( minors );
	end
	PreGame.SetPersistSettings( false );

	AutoplayLog( string.format( "start map=%s size=%s speed=%s handicap=%s majors=%d minors=%s aitweaks=%s",
		tostring( PreGame.GetMapScript() ), tostring( PreGame.GetWorldSize() ), tostring( PreGame.GetGameSpeed() ),
		tostring( PreGame.GetHandicap( 0 ) ), slot - 1, tostring( PreGame.GetNumMinorCivs() ),
		tostring( PreGame.GetGameOption( "GAMEOPTION_AI_TWEAKS" ) ) ) );
	AutoplaySet( "Status", "launching" );
	Events.SerialEventStartGame();
end

function HumanizedAutoplayFrontEnd()
	if AutoplayTurns() <= 0 then
		return;
	end
	local baseShowHide = ShowHideHandler;
	ContextPtr:SetShowHideHandler( function( bIsHide, bIsInit )
		baseShowHide( bIsHide, bIsInit );
		if bIsHide or AutoplayGet( "Status" ) ~= "pending" then
			return;
		end
		local waited = 0;
		ContextPtr:SetUpdate( function( fDTime )
			waited = waited + fDTime;
			if waited >= 2 then
				ContextPtr:ClearUpdate();
				AutoplaySetupAndStart();
			end
		end );
	end );
end

function HumanizedAutoplayLoadScreen()
	if AutoplayTurns() <= 0 then
		return;
	end
	Events.SequenceGameInitComplete.Add( function()
		local coachReplay = tonumber( AutoplayGet( "CoachReplay" ) ) == 1;
		if AutoplayGet( "Status" ) ~= "launching" and not coachReplay then
			return;
		end
		for slot, handicapType in string.gmatch( AutoplayGet( "Mistakes" ) or "", "(%d+)=([%w_]+)" ) do
			local handicap = GameInfo.HandicapInfos[ handicapType ];
			local player = Players[ tonumber( slot ) ];
			if handicap and player then
				player:SetMistakeHandicap( handicap.ID );
				AutoplayLog( "mistakes slot " .. slot .. " " .. handicapType );
			end
		end
		Events.LoadScreenClose();
		if coachReplay then
			Game.SetPausePlayer( Game.GetActivePlayer() );
		else
			Game.SetPausePlayer( -1 );
		end
		UI.SetDontShowPopups( false );
		AutoplaySet( "Status", "running" );
		AutoplayLog( "running" );
	end );
end

local g_improvementBuilds = nil;

local function AutoplayLandReport( turn )
	if not g_improvementBuilds then
		g_improvementBuilds = {};
		for build in GameInfo.Builds() do
			if build.ImprovementType then
				table.insert( g_improvementBuilds, build.ID );
			end
		end
	end
	for playerID = 0, ( GameDefines.MAX_MAJOR_CIVS or 22 ) - 1 do
		local player = Players[ playerID ];
		local capital = player and player:IsAlive() and player:GetCapitalCity();
		if capital then
			local area = capital:Plot():GetArea();
			local land, mine, majors, minors, free, sites = 0, 0, 0, 0, 0, 0;
			for i = 0, Map.GetNumPlots() - 1 do
				local plot = Map.GetPlotByIndex( i );
				if plot:GetArea() == area and not plot:IsWater() then
					land = land + 1;
					local owner = plot:GetOwner();
					if owner == -1 then
						free = free + 1;
						if player:CanFound( plot:GetX(), plot:GetY() ) and plot:GetFoundValue( playerID ) > 5000 then
							sites = sites + 1;
						end
					elseif owner == playerID then
						mine = mine + 1;
					elseif Players[ owner ]:IsMinorCiv() then
						minors = minors + 1;
					else
						majors = majors + 1;
					end
				end
			end
			AutoplayLog( string.format( "land turn=%d player=%d cities=%d area=%d land=%d mine=%d majors=%d minors=%d free=%d sites=%d",
				turn, playerID, player:GetNumCities(), area, land, mine, majors, minors, free, sites ) );
			local owned, improved, available = {}, {}, 0;
			for i = 0, Map.GetNumPlots() - 1 do
				local plot = Map.GetPlotByIndex( i );
				local resource = plot:GetResourceType();
				if resource ~= -1 and plot:GetOwner() == playerID and GameInfo.Resources[ resource ].ResourceClassType == "RESOURCECLASS_LUXURY" then
					owned[ resource ] = true;
					if plot:GetImprovementType() ~= -1 and not plot:IsImprovementPillaged() then
						improved[ resource ] = true;
					end
				end
			end
			local surplus, imported, exported, fromMinors = 0, 0, 0, 0;
			for resource in GameInfo.Resources( "ResourceClassType = 'RESOURCECLASS_LUXURY'" ) do
				if player:GetNumResourceAvailable( resource.ID, true ) > 0 then
					available = available + 1;
				end
				if player:GetNumResourceAvailable( resource.ID, false ) > 1 then
					surplus = surplus + 1;
				end
				imported = imported + player:GetResourceImport( resource.ID );
				exported = exported + player:GetResourceExport( resource.ID );
				fromMinors = fromMinors + player:GetResourceFromMinors( resource.ID );
			end
			local team = Teams[ player:GetTeam() ];
			local details = {};
			for resource in pairs( owned ) do
				local info = GameInfo.Resources[ resource ];
				local canImprove = false;
				for row in GameInfo.Improvement_ResourceTypes{ ResourceType = info.Type } do
					for build in GameInfo.Builds{ ImprovementType = row.ImprovementType } do
						if build.PrereqTech == nil or team:IsHasTech( GameInfoTypes[ build.PrereqTech ] ) then
							canImprove = true;
						end
					end
				end
				table.insert( details, string.format( "%s:%s%s", string.gsub( info.Type, "RESOURCE_", "" ),
					canImprove and "T" or "-", improved[ resource ] and "I" or "-" ) );
			end
			AutoplayLog( string.format( "luxury turn=%d player=%d %s", turn, playerID, table.concat( details, " " ) ) );
			local workers = {};
			for unit in player:Units() do
				if unit:GetUnitAIType() == GameInfoTypes.UNITAI_WORKER then
					table.insert( workers, unit );
				end
			end
			local worked, workedImproved, workedImprovable, workedWater = 0, 0, 0, 0;
			for i = 0, Map.GetNumPlots() - 1 do
				local plot = Map.GetPlotByIndex( i );
				if plot:GetOwner() == playerID and not plot:IsCity() and plot:IsBeingWorked() then
					worked = worked + 1;
					if plot:IsWater() then
						workedWater = workedWater + 1;
					end
					if plot:GetImprovementType() ~= -1 and not plot:IsImprovementPillaged() then
						workedImproved = workedImproved + 1;
					else
						for _, build in ipairs( g_improvementBuilds ) do
							if player:CanBuild( plot, build ) then
								workedImprovable = workedImprovable + 1;
								break;
							end
						end
					end
				end
			end
			AutoplayLog( string.format( "tiles turn=%d player=%d worked=%d improved=%d improvable=%d water=%d workers=%d",
				turn, playerID, worked, workedImproved, workedImprovable, workedWater, #workers ) );
			for i = 0, Map.GetNumPlots() - 1 do
				local plot = Map.GetPlotByIndex( i );
				local resource = plot:GetResourceType();
				if resource ~= -1 and plot:GetOwner() == playerID and GameInfo.Resources[ resource ].ResourceClassType == "RESOURCECLASS_LUXURY"
					and ( plot:GetImprovementType() == -1 or plot:IsImprovementPillaged() ) then
					local info = GameInfo.Resources[ resource ];
					local can = 0;
					for row in GameInfo.Improvement_ResourceTypes{ ResourceType = info.Type } do
						for build in GameInfo.Builds{ ImprovementType = row.ImprovementType } do
							if player:CanBuild( plot, build.ID ) then
								can = 1;
							end
						end
					end
					local cityDist = 99;
					for city in player:Cities() do
						cityDist = math.min( cityDist, Map.PlotDistance( city:GetX(), city:GetY(), plot:GetX(), plot:GetY() ) );
					end
					local workerDist, busy, sameArea = 99, 0, 0;
					for _, unit in ipairs( workers ) do
						workerDist = math.min( workerDist, Map.PlotDistance( unit:GetX(), unit:GetY(), plot:GetX(), plot:GetY() ) );
						if unit:GetBuildType() ~= -1 then
							busy = busy + 1;
						end
						if unit:GetPlot():GetArea() == plot:GetArea() then
							sameArea = 1;
						end
					end
					AutoplayLog( string.format( "luxplot turn=%d player=%d res=%s x=%d y=%d can=%d water=%d citydist=%d radius=%d worked=%d danger=%d feature=%d workers=%d busy=%d workerdist=%d samearea=%d",
						turn, playerID, string.gsub( info.Type, "RESOURCE_", "" ), plot:GetX(), plot:GetY(), can, plot:IsWater() and 1 or 0, cityDist,
						plot:IsWithinTeamCityRadius( player:GetTeam() ) and 1 or 0, plot:IsBeingWorked() and 1 or 0,
						player:GetPlotDanger( plot ), plot:GetFeatureType(), #workers, busy, workerDist, sameArea ) );
				end
			end
			local function count( t )
				local n = 0;
				for _ in pairs( t ) do
					n = n + 1;
				end
				return n;
			end
			AutoplayLog( string.format( "happy turn=%d player=%d happy=%d unhappy=%d excess=%d lux=%d build=%d policy=%d relig=%d minor=%d cities=%d nw=%d luxOwned=%d luxImproved=%d luxAvail=%d luxSurplus=%d luxImport=%d luxExport=%d luxMinors=%d ucity=%d upop=%d",
				turn, playerID, player:GetHappiness(), player:GetUnhappiness(), player:GetExcessHappiness(),
				player:GetHappinessFromResources(), player:GetHappinessFromBuildings(), player:GetHappinessFromPolicies(),
				player:GetHappinessFromReligion(), player:GetHappinessFromMinorCivs(), player:GetHappinessFromCities(),
				player:GetHappinessFromNaturalWonders(), count( owned ), count( improved ), available, surplus, imported, exported, fromMinors,
				player:GetUnhappinessFromCityCount(), player:GetUnhappinessFromCityPopulation() ) );
		end
	end
end

function HumanizedAutoplayInGame()
	local turns = AutoplayTurns();
	if turns <= 0 then
		return;
	end
	if tonumber( AutoplayGet( "Supervise" ) ) == 1 then
		g_superviseContext = ContextPtr:LoadNewContext( "HumanizedSupervise" );
	end
	local baseUpdate = OnUpdate;
	local lastTurn = -1;
	local finished = false;
	ContextPtr:SetUpdate( function( fDTime )
		baseUpdate( fDTime );
		if finished then
			return;
		end
		local turn = Game.GetGameTurn();
		local over = Game.GetGameState() ~= GameplayGameStateTypes.GAMESTATE_ON;
		if turn == lastTurn and not over then
			return;
		end
		lastTurn = turn;
		if AutoplayGet( "Status" ) ~= "running" then
			finished = true;
			AutoplayLog( "stopped at turn " .. turn );
			UI.ExitGame();
			return;
		end
		AutoplaySet( "Turn", turn );
		if turn == 25 or turn == 50 or turn == 75 or turn >= turns then
			local ok, err = pcall( AutoplayLandReport, turn );
			if not ok then
				AutoplayLog( "report error " .. tostring( err ) );
			end
		end
		if turn >= turns or over then
			finished = true;
			local saveAs = AutoplayGet( "SaveAs" );
			if saveAs and saveAs ~= "" then
				UI.SaveGame( saveAs );
				AutoplayLog( "saved " .. saveAs );
			end
			AutoplaySet( "Status", "done" );
			AutoplayLog( "done at turn " .. turn );
			UI.ExitGame();
		end
	end );
end
