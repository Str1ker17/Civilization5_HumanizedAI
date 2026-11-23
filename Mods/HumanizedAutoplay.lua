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

local function DumpActive()
	return ( AutoplayGet( "Dump" ) or "" ) ~= "";
end

function HumanizedAutoplayLoadScreen()
	if AutoplayTurns() <= 0 then
		return;
	end
	Events.SequenceGameInitComplete.Add( function()
		local coachReplay = tonumber( AutoplayGet( "CoachReplay" ) ) == 1;
		local status = AutoplayGet( "Status" );
		if status ~= "launching" and status ~= "reloading" and not coachReplay then
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
		if coachReplay or DumpActive() or tonumber( AutoplayGet( "View" ) ) == 1 then
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

local function DumpLog( text )
	print( "HumanizedDump: " .. text );
end

local function DumpName( info )
	return info and string.gsub( info.Type, "^[A-Z]+_", "" ) or "-";
end

local function DumpChunks( head, items )
	local chunk = {};
	local first = 1;
	for i, item in ipairs( items ) do
		table.insert( chunk, item );
		if #chunk == 100 or i == #items then
			DumpLog( string.format( "%s from=%d %s", head, first - 1, table.concat( chunk, ";" ) ) );
			chunk = {};
			first = i + 1;
		end
	end
end

local function DumpFields( t )
	local fields = {};
	for k, v in pairs( t ) do
		if type( v ) == "number" or type( v ) == "boolean" then
			table.insert( fields, k .. "=" .. tostring( v ) );
		elseif type( v ) == "string" then
			table.insert( fields, k .. "=" .. string.gsub( v, "[%s;=]", "_" ) );
		end
	end
	table.sort( fields );
	return table.concat( fields, "," );
end

local function DumpStatic()
	local function legend( name, iter )
		local t = {};
		for row in iter do
			table.insert( t, row.ID .. ":" .. DumpName( row ) );
		end
		DumpLog( "legend " .. name .. " " .. table.concat( t, "," ) );
	end
	legend( "terrain", GameInfo.Terrains() );
	legend( "feature", GameInfo.Features() );
	legend( "resource", GameInfo.Resources() );
	legend( "improvement", GameInfo.Improvements() );
	legend( "route", GameInfo.Routes() );
	legend( "specialist", GameInfo.Specialists() );
	legend( "unitclass", GameInfo.UnitClasses() );
	local items = {};
	for i = 0, Map.GetNumPlots() - 1 do
		local plot = Map.GetPlotByIndex( i );
		table.insert( items, string.format( "%d,%d,%d,%d,%d,%d,%d", plot:GetTerrainType(), plot:GetPlotType(), plot:IsRiver() and 1 or 0,
			plot:IsLake() and 1 or 0, plot:GetResourceType( -1 ), plot:GetNumResource(), plot:GetArea() ) );
	end
	DumpLog( "static fields=terrain,plottype,river,lake,resource,amount,area index=y*width+x" );
	DumpChunks( "static", items );
	local options = {};
	for option in GameInfo.GameOptions() do
		table.insert( options, option.Type .. "=" .. tostring( PreGame.GetGameOption( option.Type ) ) );
	end
	for _, name in ipairs( { "GAMEOPTION_DUEL_STUFF", "GAMEOPTION_TOURNAMENT_MODE", "GAMEOPTION_NO_LEAGUES", "GAMEOPTION_NO_ESPIONAGE", "GAMEOPTION_AI_TWEAKS" } ) do
		table.insert( options, name .. "=" .. tostring( PreGame.GetGameOption( name ) ) );
	end
	DumpLog( "options " .. table.concat( options, " " ) );
	for i = 0, GameDefines.MAX_PLAYERS - 1 do
		local player = Players[ i ];
		if player and player:IsEverAlive() then
			DumpLog( string.format( "slot id=%d civ=%s handicap=%s team=%d minor=%s", i, DumpName( GameInfo.Civilizations[ player:GetCivilizationType() ] ),
				DumpName( GameInfo.HandicapInfos[ player:GetHandicapType() ] ), player:GetTeam(), tostring( player:IsMinorCiv() ) ) );
		end
	end
end

local function DumpState()
	local turn = Game.GetGameTurn();
	DumpLog( string.format( "state turn=%d map=%s size=%s grid=%dx%d", turn, tostring( PreGame.GetMapScript() ),
		tostring( PreGame.GetWorldSize() ), Map.GetGridSize() ) );
	if tonumber( AutoplayGet( "DumpIndex" ) ) == tonumber( AutoplayGet( "DumpFrom" ) ) then
		DumpStatic();
	end

	local plotStats = {};
	local camps = {};
	local items = {};
	for i = 0, Map.GetNumPlots() - 1 do
		local plot = Map.GetPlotByIndex( i );
		local owner = plot:GetOwner();
		local s = plotStats[ owner ];
		if not s then
			s = { plots = 0, routes = 0, routesPillaged = 0, improved = 0, pillaged = 0 };
			plotStats[ owner ] = s;
		end
		s.plots = s.plots + 1;
		local route = plot:GetRouteType();
		if route ~= -1 then
			s.routes = s.routes + 1;
			if plot:IsRoutePillaged() then
				s.routesPillaged = s.routesPillaged + 1;
			end
		end
		local improvement = plot:GetImprovementType();
		if improvement ~= -1 then
			s.improved = s.improved + 1;
			if plot:IsImprovementPillaged() then
				s.pillaged = s.pillaged + 1;
			end
			if improvement == GameInfoTypes.IMPROVEMENT_BARBARIAN_CAMP then
				table.insert( camps, plot:GetX() .. ":" .. plot:GetY() );
			end
		end
		local worked = -1;
		if plot:IsBeingWorked() then
			local city = plot:GetWorkingCity();
			worked = city and city:GetID() or -2;
		end
		table.insert( items, string.format( "%d,%d,%d%s,%d%s,%d", owner, worked, improvement, plot:IsImprovementPillaged() and "p" or "",
			route, plot:IsRoutePillaged() and "p" or "", plot:GetFeatureType() ) );
	end
	DumpLog( string.format( "mapfields turn=%d fields=owner,workedcity,improvement(p=pillaged),route(p=pillaged),feature", turn ) );
	DumpChunks( string.format( "map turn=%d", turn ), items );
	DumpLog( string.format( "camps turn=%d %s", turn, table.concat( camps, ";" ) ) );

	local activities = {};
	for name, value in pairs( ActivityTypes or {} ) do
		activities[ value ] = string.gsub( name, "^ACTIVITY_", "" );
	end
	local majors = {};
	for i = 0, ( GameDefines.MAX_MAJOR_CIVS or 22 ) - 1 do
		if Players[ i ] and Players[ i ]:IsAlive() then
			table.insert( majors, i );
		end
	end

	for i = 0, GameDefines.MAX_PLAYERS - 1 do
		local player = Players[ i ];
		if player and player:IsAlive() then
			local team = Teams[ player:GetTeam() ];
			local s = plotStats[ i ] or { plots = 0, routes = 0, routesPillaged = 0, improved = 0, pillaged = 0 };
			if not player:IsBarbarian() then
				local wars = {};
				for j = 0, GameDefines.MAX_PLAYERS - 1 do
					local other = Players[ j ];
					if j ~= i and other and other:IsAlive() and not other:IsBarbarian() and team:IsAtWar( other:GetTeam() ) then
						table.insert( wars, j );
					end
				end
				local research = player:GetCurrentResearch();
				DumpLog( string.format( "player turn=%d id=%d civ=%s human=%d minor=%d cities=%d gold=%d gpt=%d conn=%.1f citygold=%.1f unitcost=%d buildmaint=%d impmaint=%d science=%d techs=%d research=%s rprog=%d rcost=%d culture=%d culturetotal=%d policies=%d nextpolicy=%d happy=%d happiness=%d unhappiness=%d might=%d units=%d plots=%d routes=%d routespill=%d improved=%d pillaged=%d faith=%d faithpt=%d pantheon=%d religion=%d ga=%d gameter=%d gathreshold=%d gp=%d gg=%d ggxp=%d score=%d tourism=%d era=%d wars=%s",
					turn, i, DumpName( GameInfo.Civilizations[ player:GetCivilizationType() ] ), player:IsHuman() and 1 or 0, player:IsMinorCiv() and 1 or 0,
					player:GetNumCities(), player:GetGold(), player:CalculateGoldRate(), player:GetCityConnectionGoldTimes100() / 100,
					player:GetGoldFromCitiesMinusTradeRoutesTimes100() / 100, player:CalculateUnitCost(), player:GetBuildingGoldMaintenance(),
					player:GetImprovementGoldMaintenance(), player:GetScience(), team:GetTeamTechs():GetNumTechsKnown(),
					DumpName( GameInfo.Technologies[ research ] ), research ~= -1 and player:GetResearchProgress( research ) or 0,
					research ~= -1 and player:GetResearchCost( research ) or 0, player:GetTotalJONSCulturePerTurn(), player:GetJONSCulture(),
					player:GetNumPolicies(), player:GetNextPolicyCost(), player:GetExcessHappiness(), player:GetHappiness(), player:GetUnhappiness(),
					player:GetMilitaryMight(), player:GetNumUnits(), s.plots, s.routes, s.routesPillaged, s.improved, s.pillaged,
					player:GetFaith(), player:GetTotalFaithPerTurn(), player:HasCreatedPantheon() and player:GetBeliefInPantheon() or -1,
					player:HasCreatedReligion() and player:GetReligionCreatedByPlayer() or -1, player:GetGoldenAgeTurns(), player:GetGoldenAgeProgressMeter(),
					player:GetGoldenAgeProgressThreshold(), player:GetGreatPeopleCreated(), player:GetGreatGeneralsCreated(), player:GetCombatExperience(),
					player:GetScore(), player:GetTourism(), player:GetCurrentEra(), table.concat( wars, "," ) ) );
				local techs = {};
				for tech in GameInfo.Technologies() do
					if team:IsHasTech( tech.ID ) then
						table.insert( techs, DumpName( tech ) );
					end
				end
				DumpLog( string.format( "techs turn=%d id=%d %s", turn, i, table.concat( techs, "," ) ) );
				local policies = {};
				for policy in GameInfo.Policies() do
					if player:HasPolicy( policy.ID ) then
						table.insert( policies, DumpName( policy ) );
					end
				end
				DumpLog( string.format( "policies turn=%d id=%d %s", turn, i, table.concat( policies, "," ) ) );
				local resources = {};
				for resource in GameInfo.Resources() do
					local total = player:GetNumResourceTotal( resource.ID, true );
					local available = player:GetNumResourceAvailable( resource.ID, true );
					local used = player:GetNumResourceUsed( resource.ID );
					if total ~= 0 or available ~= 0 or used ~= 0 then
						table.insert( resources, string.format( "%s:%d/%d/%d", DumpName( resource ), available, used, total ) );
					end
				end
				DumpLog( string.format( "resources turn=%d id=%d available/used/total %s", turn, i, table.concat( resources, "," ) ) );
				local routesList = {};
				local ok, list = pcall( function() return player:GetTradeRoutes(); end );
				if ok and list then
					for _, r in ipairs( list ) do
						table.insert( routesList, DumpFields( r ) );
					end
				end
				DumpLog( string.format( "trade turn=%d id=%d %s", turn, i, table.concat( routesList, ";" ) ) );
				if player:IsMinorCiv() then
					local friends = {};
					for _, m in ipairs( majors ) do
						table.insert( friends, m .. ":" .. player:GetMinorCivFriendshipWithMajor( m ) );
					end
					DumpLog( string.format( "minor turn=%d id=%d friendship=%s", turn, i, table.concat( friends, "," ) ) );
				end
			end
			for city in player:Cities() do
				local buildings = {};
				for building in GameInfo.Buildings() do
					if city:IsHasBuilding( building.ID ) then
						table.insert( buildings, DumpName( building ) );
					end
				end
				local specialists = {};
				for specialist in GameInfo.Specialists() do
					local count = city:GetSpecialistCount( specialist.ID );
					local progress = city:GetSpecialistGreatPersonProgress( specialist.ID );
					if count > 0 or progress > 0 then
						table.insert( specialists, string.format( "%s:%d:%d", DumpName( specialist ), count, progress ) );
					end
				end
				DumpLog( string.format( "city turn=%d owner=%d id=%d name=%s x=%d y=%d pop=%d food=%d prod=%d gold=%d sci=%d cult=%d faith=%d build=%s left=%d stored=%d needed=%d foodstored=%d foodneeded=%d growleft=%d focus=%d capital=%d connected=%d damage=%d maxhp=%d strength=%d garrison=%d puppet=%d occupied=%d razing=%d resistance=%d original=%d religion=%d works=%d borderstored=%d borderneeded=%d specialists=%s",
					turn, i, city:GetID(), string.gsub( city:GetName(), "%s", "_" ), city:GetX(), city:GetY(), city:GetPopulation(), city:GetYieldRate( YieldTypes.YIELD_FOOD ),
					city:GetYieldRate( YieldTypes.YIELD_PRODUCTION ), city:GetYieldRate( YieldTypes.YIELD_GOLD ), city:GetYieldRate( YieldTypes.YIELD_SCIENCE ),
					city:GetJONSCulturePerTurn(), city:GetFaithPerTurn(),
					string.gsub( Locale.ConvertTextKey( city:GetProductionNameKey() or "" ), "%s", "_" ), city:GetProductionTurnsLeft(),
					city:GetProduction(), city:GetProductionNeeded(), city:GetFood(), city:GrowthThreshold(), city:GetFoodTurnsLeft(), city:GetFocusType(),
					city:IsCapital() and 1 or 0, ( city:IsCapital() or player:IsCapitalConnectedToCity( city ) ) and 1 or 0, city:GetDamage(), city:GetMaxHitPoints(),
					math.floor( city:GetStrengthValue() / 100 ), city:GetGarrisonedUnit() and 1 or 0, city:IsPuppet() and 1 or 0, city:IsOccupied() and 1 or 0,
					city:IsRazing() and 1 or 0, city:IsResistance() and 1 or 0, city:GetOriginalOwner(), city:GetReligiousMajority(), city:GetNumGreatWorks(),
					city:GetJONSCultureStored(), city:GetJONSCultureThreshold(), table.concat( specialists, "," ) ) );
				DumpLog( string.format( "buildings turn=%d owner=%d id=%d %s", turn, i, city:GetID(), table.concat( buildings, "," ) ) );
			end
			for unit in player:Units() do
				local promotions = {};
				if unit:GetLevel() > 1 or unit:GetExperience() > 0 then
					for promotion in GameInfo.UnitPromotions() do
						if unit:IsHasPromotion( promotion.ID ) then
							table.insert( promotions, DumpName( promotion ) );
						end
					end
				end
				local build = unit:GetBuildType();
				local buildInfo = build ~= -1 and GameInfo.Builds[ build ];
				DumpLog( string.format( "unit turn=%d owner=%d id=%d type=%s ai=%s x=%d y=%d damage=%d str=%d rstr=%d level=%d xp=%d domain=%d embarked=%d act=%s fort=%d auto=%d build=%s buildprog=%d promos=%s",
					turn, i, unit:GetID(), DumpName( GameInfo.Units[ unit:GetUnitType() ] ), DumpName( GameInfo.UnitAIInfos[ unit:GetUnitAIType() ] ),
					unit:GetX(), unit:GetY(), unit:GetDamage(), unit:GetBaseCombatStrength(), unit:GetBaseRangedCombatStrength(), unit:GetLevel(),
					unit:GetExperience(), unit:GetDomainType(), unit:IsEmbarked() and 1 or 0, activities[ unit:GetActivityType() ] or tostring( unit:GetActivityType() ),
					unit:GetFortifyTurns(), unit:IsAutomated() and 1 or 0, buildInfo and DumpName( buildInfo ) or "-",
					buildInfo and unit:GetPlot():GetBuildProgress( build ) or 0, table.concat( promotions, "," ) ) );
			end
		end
	end
	if tonumber( AutoplayGet( "DumpIndex" ) ) == tonumber( AutoplayGet( "DumpTo" ) ) then
		for i = 0, ( GameDefines.MAX_MAJOR_CIVS or 22 ) - 1 do
			local player = Players[ i ];
			if player and player:IsEverAlive() then
				local ok, data = pcall( function() return player:GetReplayData(); end );
				if ok and data then
					for set, values in pairs( data ) do
						local points = {};
						for t, v in pairs( values ) do
							table.insert( points, t .. ":" .. v );
						end
						DumpLog( string.format( "replay id=%d set=%s %s", i, tostring( set ), table.concat( points, "," ) ) );
					end
				end
			end
		end
	end
	DumpLog( string.format( "end turn=%d", turn ) );
end

local function DumpNext()
	local index = ( tonumber( AutoplayGet( "DumpIndex" ) ) or tonumber( AutoplayGet( "DumpFrom" ) ) or 0 ) + 1;
	local last = tonumber( AutoplayGet( "DumpTo" ) ) or 0;
	if index > last then
		return false;
	end
	local dir = string.match( AutoplayGet( "LoadFile" ) or "", "^(.*[\\/])" ) or "";
	local path = dir .. string.format( AutoplayGet( "Dump" ), index ) .. ".Civ5Save";
	AutoplaySet( "DumpIndex", index );
	AutoplaySet( "Status", "reloading" );
	DumpLog( "load " .. path );
	Events.PlayerChoseToLoadGame( path );
	return true;
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
		if tonumber( AutoplayGet( "View" ) ) == 1 then
			finished = true;
			AutoplayLog( "view mode at turn " .. turn );
			return;
		end
		if DumpActive() then
			finished = true;
			local ok, err = pcall( DumpState );
			if not ok then
				DumpLog( "error " .. tostring( err ) );
			end
			if not DumpNext() then
				AutoplaySet( "Status", "done" );
				AutoplayLog( "done at turn " .. turn );
				UI.ExitGame();
			end
			return;
		end
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
