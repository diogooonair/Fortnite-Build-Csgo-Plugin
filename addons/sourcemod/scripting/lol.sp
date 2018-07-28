#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#define NAME "Fortnite Build"
#define AUTHOR "Diogoonair"
#define DESCRIPTION "Build Fortnite constructions"
#define VERSION "1.5"
#define URL "http://steamcommunity.com/id/diogo218dv"

char g_sPropsPath[PLATFORM_MAX_PATH];
char g_sShowProp[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
int g_iPropEnt[MAXPLAYERS + 1] =  { INVALID_ENT_REFERENCE, ... };

ConVar cv_sSoundPath;
ConVar cv_fAmbientSoundVolume;
ConVar cv_iPropHealth;
ConVar cv_fMaxDistance;

float vOldAng[MAXPLAYERS + 1][3];
bool bAllowPlacing[MAXPLAYERS + 1];

public Plugin myinfo =  { name = NAME, author = AUTHOR, description = DESCRIPTION, version = VERSION, url = URL };

// --------------- STARTUP --------------- //
public void OnPluginStart()
{
	
	cv_sSoundPath = CreateConVar("sm_props_sound", "fortnite/wood_lev_01_construction_loop_a.mp3", "Sounds to be played on prop spawn | Edit only before map change");
	cv_fAmbientSoundVolume = CreateConVar("sm_props_sound_volume", "1.0", "Volume of the ambient sound", _, true, 0.0, true, 1.0);
	cv_iPropHealth = CreateConVar("sm_props_health", "150", "Props Ent health 0 - Infinite", _, true, 0.0);
	cv_fMaxDistance = CreateConVar("sm_props_max_distance", "150", "Max distance where a prop can be placed. 0 - Unlimited", _, true, 0.0);
	AutoExecConfig(true);
	
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	
	BuildPath(Path_SM, g_sPropsPath, sizeof(g_sPropsPath), "configs/builds.txt");
	
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_death", Event_PlayerDeath);
}

public void OnMapStart()
{
	char sSoundPath[PLATFORM_MAX_PATH];
	cv_sSoundPath.GetString(sSoundPath, sizeof(sSoundPath));
	if (strlen(sSoundPath) > 0)
	{
		PrecacheSound(sSoundPath);
		Format(sSoundPath, sizeof(sSoundPath), "sound/%s", sSoundPath);
		AddFileToDownloadsTable(sSoundPath);
	}
}

public bool CheckPropDatabase(char[] sCommand, char[] sModel, int iMaxLengh)
{
	char sPropModel[128];
	
	KeyValues hProps = CreateKeyValues("Props");
	
	FileToKeyValues(hProps, g_sPropsPath);
	
	KvGetString(hProps, sCommand, sPropModel, sizeof(sPropModel), "null");
	
	if (StrEqual(sPropModel, "null", true))
	{
		CloseHandle(hProps);
		
		return false;
	}
	
	CloseHandle(hProps);
	
	strcopy(sModel, iMaxLengh, sPropModel);
	
	return true;
}


// --------------- LISTENERS --------------- //
public Action Command_Say(int iClient, char[] sCommand, int iArgs)
{
	bool bIsProp;
	char sFirstArg[128], sCheckArg[128], sModel[128];
	
	GetCmdArg(1, sFirstArg, sizeof(sFirstArg));
	
	strcopy(sCheckArg, sizeof(sCheckArg), sFirstArg);
	
	if (ReplaceString(sCheckArg, sizeof(sCheckArg), "!", "") || ReplaceString(sCheckArg, sizeof(sCheckArg), "/", ""))
	{
		bIsProp = CheckPropDatabase(sCheckArg, sModel, sizeof(sModel));
	} else {
		return Plugin_Continue;
	}
	
	if (bIsProp)
	{
		if (g_iPropEnt[iClient] != INVALID_ENT_REFERENCE)
		{
			int iEnt = EntRefToEntIndex(g_iPropEnt[iClient]);
			AcceptEntityInput(iEnt, "kill");
			g_iPropEnt[iClient] = INVALID_ENT_REFERENCE;
		}
		strcopy(g_sShowProp[iClient], sizeof(g_sShowProp[]), sModel);
		return Plugin_Handled;
	} else {
		return Plugin_Continue;
	}
}

// --------------- EVENTS --------------- //
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		int iPropEnt = EntRefToEntIndex(g_iPropEnt[client]);
		if (g_iPropEnt[client] == INVALID_ENT_REFERENCE)
		{
			if (strlen(g_sShowProp[client]))
			{
				bAllowPlacing[client] = true;
				int iEnt = CreateEntityByName("prop_dynamic_override");
				PrecacheModel(g_sShowProp[client]);
				DispatchKeyValue(iEnt, "model", g_sShowProp[client]);
				DispatchSpawn(iEnt);
				SetEntityRenderMode(iEnt, RENDER_TRANSCOLOR);
				SetEntityRenderColor(iEnt, 10, 70, 200, 150);
				g_iPropEnt[client] = EntIndexToEntRef(iEnt);
				SetEntProp(iEnt, Prop_Send, "m_nSolidType", 1);
			}
		}
		else
		{
			//Dont teleport if client is not moving
			if ((vOldAng[client][0] != angles[0]) || (vOldAng[client][1] != angles[1]) || (vOldAng[client][1] != angles[1]) || 
				(buttons & IN_FORWARD) || (buttons & IN_BACK) || (buttons & IN_MOVELEFT) || (buttons & IN_MOVERIGHT) || (buttons & IN_JUMP) || (buttons & IN_DUCK)
				)
			{
				float fAngles[3], fCAngles[3], fCOrigin[3], fOrigin[3];
				
				GetClientAbsAngles(client, fAngles);
				GetClientEyePosition(client, fCOrigin);
				GetClientEyeAngles(client, fCAngles);
				
				Handle hTraceRay = TR_TraceRayFilterEx(fCOrigin, fCAngles, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf, client);
				if (TR_DidHit(hTraceRay))
				{
					TR_GetEndPosition(fOrigin, hTraceRay);
					CloseHandle(hTraceRay);
				} else return Plugin_Continue;
				
				TeleportEntity(iPropEnt, fOrigin, NULL_VECTOR, NULL_VECTOR);
				vOldAng[client][0] = angles[0];
				vOldAng[client][1] = angles[1];
				vOldAng[client][2] = angles[2];
				
				float fDistance = GetVectorDistance(fCOrigin, fOrigin);
				if (bAllowPlacing[client] && fDistance > cv_fMaxDistance.FloatValue)
				{
					SetEntityRenderColor(iPropEnt, 255, 70, 10, 150);
					bAllowPlacing[client] = false;
				}
				else if (!bAllowPlacing[client] && fDistance <= cv_fMaxDistance.FloatValue)
				{
					bAllowPlacing[client] = true;
					SetEntityRenderColor(iPropEnt, 10, 70, 200, 150);
				}
				
			}
			
			if (buttons & IN_ATTACK)
			{
				buttons &= ~IN_ATTACK;
				if (!bAllowPlacing[client])
					return Plugin_Changed;
				
				ArrayList data = new ArrayList();
				data.Push(client);
				data.Push(iPropEnt);
				CreateTimer(0.0, Timer_UpdateProp, data); //We need this or the left click wont be removed
				
				return Plugin_Changed;
			}
			
			if (buttons & IN_ATTACK2)
			{
				buttons &= ~IN_ATTACK2;
				AcceptEntityInput(iPropEnt, "kill");
				g_iPropEnt[client] = INVALID_ENT_REFERENCE;
				g_sShowProp[client] = "";
				
				return Plugin_Changed;
			}
			
			if (buttons & IN_RELOAD)
			{
				buttons &= ~IN_RELOAD;
				float vAngles[3];
				GetEntPropVector(iPropEnt, Prop_Data, "m_angRotation", vAngles);
				vAngles[0] += 0.0;
				vAngles[1] += 10.0;
				vAngles[2] += 0.0;
				TeleportEntity(iPropEnt, NULL_VECTOR, vAngles, NULL_VECTOR);
			}
		}
	}
	return Plugin_Continue;
}

// --------------- HOOKS --------------- //
public void Event_PlayerDeath(Event event, const char[] name, bool bDontbroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (g_iPropEnt[client] != INVALID_ENT_REFERENCE)
	{
		int iEnt = EntRefToEntIndex(g_iPropEnt[client]);
		AcceptEntityInput(iEnt, "kill");
		g_iPropEnt[client] = INVALID_ENT_REFERENCE;
	}
	g_sShowProp[client] = "";
}

public void Event_RoundEnd(Event event, const char[] name, bool bDontbroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_sShowProp[i] = "";
		if (g_iPropEnt[i] != INVALID_ENT_REFERENCE)
		{
			int iEnt = EntRefToEntIndex(g_iPropEnt[i]);
			AcceptEntityInput(iEnt, "kill");
			g_iPropEnt[i] = INVALID_ENT_REFERENCE;
		}
	}
}

public void Hook_TraceAttackPost(int victim, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup)
{
	static int iGameTick;
	
	if (iGameTick != GetGameTickCount()) 
	{
		int r, g, b, a;
		GetEntityRenderColor(victim, r, g, b, a);
		if (r == 255 && g == 255 && b == 255)
			SetEntityRenderColor(victim, 255, 30, 40);
		else
			SetEntityRenderColor(victim, r - RoundToNearest(damage), g, b);
		iGameTick = GetGameTickCount();
	}
}

// --------------- TIMERS --------------- //
public Action Timer_UpdateProp(Handle timer, ArrayList data)
{
	int client = data.Get(0);
	int iPropEnt = data.Get(1);
	data.Close();
	SetEntityRenderColor(iPropEnt);
	SetEntProp(iPropEnt, Prop_Send, "m_nSolidType", 6);
	
	if (cv_iPropHealth.IntValue > 0)
	{
		SetEntProp(iPropEnt, Prop_Data, "m_takedamage", 2);
		SetEntProp(iPropEnt, Prop_Data, "m_iHealth", cv_iPropHealth.IntValue);
	}
	
	float vOrigin[3];
	GetEntityOrigin(iPropEnt, vOrigin);
	
	char sSoundPath[PLATFORM_MAX_PATH];
	cv_sSoundPath.GetString(sSoundPath, sizeof(sSoundPath));
	if (strlen(sSoundPath) > 0)
		EmitAmbientSound(sSoundPath, vOrigin, _, _, _, cv_fAmbientSoundVolume.FloatValue);
	
	SDKHook(iPropEnt, SDKHook_TraceAttackPost, Hook_TraceAttackPost);
	g_iPropEnt[client] = INVALID_ENT_REFERENCE;
	g_sShowProp[client] = "";
} 

// --------------- STOCKS & FILTERS --------------- //
public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	if (entity != data)
	{
		return true;
	}
	return false;
}

stock void GetEntityOrigin(int entity, float origin[3])
{
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
}