#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <autoexecconfig>
#include <websocket>
#include <ripext>
#include <steamworks>

#tryinclude <morecolors>
#if !defined _colors_included
  #include <multicolors>
#endif

#define PLUGIN_VERSION "1.1"

char g_sHostname[64];
char g_sHost[64] = "127.0.0.1";
char g_sToken[64];
char g_sPrefix[8];

int g_iPort = 57452;
int g_iFlag;

bool g_bFlag;

// Core convars
ConVar g_cHost;
ConVar g_cPort;
ConVar g_cPrefix;
ConVar g_cFlag;
ConVar g_cHostname;
ConVar g_cAllowRemoteCommands;

// Display format convars
ConVar g_cChatFormat;
ConVar g_cEventFormat;

// Event convars
ConVar g_cPlayerEvent;
ConVar g_cBotPlayerEvent;
ConVar g_cMapEvent;

// WebSocket connection handle
WebSocket g_hWebSocket;

// Forward handles
Handle g_hMessageSendForward;
Handle g_hMessageReceiveForward;
Handle g_hEventSendForward;
Handle g_hEventReceiveForward;
Handle g_hCommandReceiveForward;

EngineVersion g_evEngine;

#include "include/scr"
#include "scr/messages.sp"

public Plugin myinfo = 
{
  name = "Source Chat Relay", 
  author = "ampere", 
  description = "Rewrite of Source Chat Relay by Fishy", 
  version = PLUGIN_VERSION, 
  url = "https://github.com/maxijabase"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  RegPluginLibrary("scr");
  
  CreateNative("SCR_SendMessage", Native_SendMessage);
  CreateNative("SCR_SendEvent", Native_SendEvent);
  
  return APLRes_Success;
}

public void OnPluginStart()
{
  AutoExecConfig_SetCreateFile(true);
  AutoExecConfig_SetFile("scr");
  
  AutoExecConfig_CreateConVar("scr_version", PLUGIN_VERSION, "Source Chat Relay Version", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
  
  g_cHost = AutoExecConfig_CreateConVar("scr_host", "127.0.0.1", "Relay Server Host", FCVAR_PROTECTED);
  g_cPort = AutoExecConfig_CreateConVar("scr_port", "57452", "Relay Server Port", FCVAR_PROTECTED);
  g_cPrefix = AutoExecConfig_CreateConVar("scr_prefix", "", "Prefix required to send message to Discord. If empty, none is required.", FCVAR_NONE);
  g_cFlag = AutoExecConfig_CreateConVar("scr_flag", "", "If prefix is enabled, this admin flag is required to send message using the prefix", FCVAR_PROTECTED);
  g_cHostname = AutoExecConfig_CreateConVar("scr_hostname", "", "The hostname/displayname to send with messages. If left empty, it will use the server's hostname", FCVAR_NONE);
  g_cAllowRemoteCommands = AutoExecConfig_CreateConVar("scr_allow_remote_commands", "1", "Allow authorized Discord operators (see /op) to run server commands via the relay", FCVAR_PROTECTED, true, 0.0, true, 1.0);
  g_cChatFormat = AutoExecConfig_CreateConVar("scr_chat_format", "", "Format string for incoming chat messages, using ordered string arguments in this order: entity, name, message. If empty, uses the built-in default.", FCVAR_NONE);
  g_cEventFormat = AutoExecConfig_CreateConVar("scr_event_format", "", "Format string for incoming events, using ordered string arguments in this order: entity, event, data. If empty, uses the built-in default.", FCVAR_NONE);
  
  AutoExecConfig_CleanFile();
  AutoExecConfig_ExecuteFile();

  // Start basic event convars
  g_cPlayerEvent = AutoExecConfig_CreateConVar("scr_event_player", "0", "Enable player connect/disconnect events", FCVAR_NONE, true, 0.0, true, 1.0);
  g_cBotPlayerEvent = AutoExecConfig_CreateConVar("scr_event_botplayer", "0", "Enable bot player connect/disconnect events", FCVAR_NONE, true, 0.0, true, 1.0);
  g_cMapEvent = AutoExecConfig_CreateConVar("scr_event_map", "0", "Enable map start/end events", FCVAR_NONE, true, 0.0, true, 1.0);
  
  g_hMessageSendForward = CreateGlobalForward("SCR_OnMessageSend", ET_Event, Param_Cell, Param_String, Param_String);
  g_hMessageReceiveForward = CreateGlobalForward("SCR_OnMessageReceive", ET_Event, Param_String, Param_Cell, Param_String, Param_String, Param_String);
  g_hEventSendForward = CreateGlobalForward("SCR_OnEventSend", ET_Event, Param_String, Param_String);
  g_hEventReceiveForward = CreateGlobalForward("SCR_OnEventReceive", ET_Event, Param_String, Param_String);
  g_hCommandReceiveForward = CreateGlobalForward("SCR_OnCommandReceive", ET_Event, Param_String, Param_String);
  
  g_evEngine = GetEngineVersion();
  
  // Hook player connect and disconnect events separately
  HookEvent("player_connect", Event_OnPlayerConnectionChange);
  HookEvent("player_disconnect", Event_OnPlayerConnectionChange);
}

public void OnConfigsExecuted()
{
  g_cHostname.GetString(g_sHostname, sizeof g_sHostname);
  
  if (strlen(g_sHostname) == 0)
  {
    FindConVar("hostname").GetString(g_sHostname, sizeof g_sHostname);
  }
  
  g_cHost.GetString(g_sHost, sizeof g_sHost);
  g_cPrefix.GetString(g_sPrefix, sizeof g_sPrefix);
  g_iPort = g_cPort.IntValue;
  
  char flag[8];
  g_cFlag.GetString(flag, sizeof flag);
  
  if (strlen(flag) != 0)
  {
    AdminFlag adminFlag;
    g_bFlag = FindFlagByChar(flag[0], adminFlag);
    g_iFlag = FlagToBit(adminFlag);
  }
  
  int ip[4];
  SteamWorks_GetPublicIP(ip);
  char sIP[64];
  Format(sIP, sizeof sIP, "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
  
  File file;
  char configPath[PLATFORM_MAX_PATH];
  BuildPath(Path_SM, configPath, sizeof configPath, "data/%s_%d.data", sIP, Server_GetPort());
  
  if (FileExists(configPath, false))
  {
    file = OpenFile(configPath, "r", false);
    file.ReadString(g_sToken, sizeof g_sToken, -1);
  } else
  {
    file = OpenFile(configPath, "w", false);
    GenerateRandomChars(g_sToken, sizeof g_sToken, 64);
    file.WriteString(g_sToken, true);
  }
  
  delete file;
  
  // If we're already connected, this is a convar-only reload, don't
  // reconnect, just re-announce the map like the pre-rewrite behavior did.
  if (g_hWebSocket != null && g_hWebSocket.Connected)
  {
    if (g_cMapEvent.BoolValue)
    {
      char map[64];
      GetCurrentMap(map, sizeof map);
      DispatchEvent("Map Start", map);
    }
    return;
  }
  
  ConnectRelay();
}

void ConnectRelay()
{
  if (g_hWebSocket != null)
  {
    delete g_hWebSocket;
  }
  
  char sUrl[128];
  Format(sUrl, sizeof sUrl, "ws://%s:%d", g_sHost, g_iPort);
  
  // Plain text mode: JSON payloads are encoded/decoded with ripext rather
  // than the WebSocket extension's own JSON mode, since sm-ext-json's JSON
  // methodmap collides with ripext's.
  g_hWebSocket = new WebSocket(sUrl, WebSocket_STRING);
  
  g_hWebSocket.SetOpenCallback(OnWsOpen);
  g_hWebSocket.SetMessageCallback(OnWsMessage);
  g_hWebSocket.SetCloseCallback(OnWsClose);
  g_hWebSocket.SetErrorCallback(OnWsError);
  
  g_hWebSocket.AutoReconnect = true;
  g_hWebSocket.MinReconnectWait = 1000;
  g_hWebSocket.MaxReconnectWait = 30000;
  
  g_hWebSocket.Connect();
}

/**
 * Serializes a message to the relay if connected, and always frees the handle.
 */
void SendToRelay(JSONObject obj)
{
  if (g_hWebSocket != null && g_hWebSocket.Connected)
  {
    // Sized to comfortably fit a commandResponse message: captured command
    // output (MAX_COMMAND_OUTPUT_LENGTH) plus JSON escaping overhead (e.g.
    // newlines becoming "\n") on top of the other, much shorter message
    // types this also serializes.
    char buffer[32768];
    
    if (obj.ToString(buffer, sizeof buffer))
    {
      g_hWebSocket.WriteString(buffer);
    }
    else
    {
      LogError("Failed to serialize outgoing message (buffer too small?)");
    }
  }
  
  delete obj;
}

public void OnWsOpen(WebSocket ws)
{
  SendToRelay(BuildAuthenticateMessage(g_sToken));
  LogMessage("WebSocket connected, sent authenticate request");
}

public void OnWsMessage(WebSocket ws, const char[] message, int wireSize)
{
  JSONObject obj = JSONObject.FromString(message);
  
  if (obj == null)
  {
    LogError("Received malformed JSON from relay: %s", message);
    return;
  }
  
  HandleMessage(obj);
  delete obj;
}

public void OnWsClose(WebSocket ws, int code, const char[] reason)
{
  LogMessage("WebSocket closed (code %d): %s", code, reason);
}

public void OnWsError(WebSocket ws, const char[] errMsg)
{
  LogError("WebSocket error: %s", errMsg);
}

void HandleMessage(JSONObject obj)
{
  char type[32];
  
  if (!obj.GetString("type", type, sizeof type))
  {
    return;
  }
  
  if (StrEqual(type, "chat"))
  {
    HandleChatMessage(obj);
  }
  else if (StrEqual(type, "event"))
  {
    HandleEventMessage(obj);
  }
  else if (StrEqual(type, "authenticateResponse"))
  {
    HandleAuthResponse(obj);
  }
  else if (StrEqual(type, "command"))
  {
    HandleCommandMessage(obj);
  }
}

void HandleChatMessage(JSONObject obj)
{
  char entity[64];
  char sIdType[16];
  char id[64];
  char name[MAX_NAME_LENGTH];
  char message[MAX_COMMAND_LENGTH];
  
  obj.GetString("entityName", entity, sizeof entity);
  obj.GetString("idType", sIdType, sizeof sIdType);
  obj.GetString("id", id, sizeof id);
  obj.GetString("username", name, sizeof name);
  obj.GetString("message", message, sizeof message);
  
  IdentificationType idType = StringToIdType(sIdType);
  
  // Strip anything beyond 3 bytes for character as chat can't render it
  StripCharsByBytes(entity, sizeof entity);
  StripCharsByBytes(name, sizeof name);
  StripCharsByBytes(message, sizeof message);
  
  Action result;
  
  Call_StartForward(g_hMessageReceiveForward);
  Call_PushString(entity);
  Call_PushCell(idType);
  Call_PushString(id);
  Call_PushStringEx(name, sizeof name, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_PushStringEx(message, sizeof message, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_Finish(result);
  
  if (result >= Plugin_Handled)
  {
    return;
  }
  
  char format[256];
  g_cChatFormat.GetString(format, sizeof format);
  
  if (strlen(format) > 0)
  {
    // Bound as %s arguments rather than substituted into the template text,
    // so a chat message containing a literal '%' (e.g. "50% hp") can't be
    // misparsed as a format specifier by CPrintToChatAll.
    CPrintToChatAll(format, entity, name, message);
  }
  else if (SupportsHexColor(g_evEngine))
  {
    CPrintToChatAll("{gold}[%s] {azure}%s{white}: {grey}%s", entity, name, message);
  }
  else
  {
    CPrintToChatAll("\x10[%s] \x0C%s\x01: \x08%s", entity, name, message);
  }
}

void HandleEventMessage(JSONObject obj)
{
  char entity[64];
  char event[MAX_EVENT_NAME_LENGTH];
  char data[MAX_COMMAND_LENGTH];
  
  obj.GetString("entityName", entity, sizeof entity);
  obj.GetString("event", event, sizeof event);
  obj.GetString("data", data, sizeof data);
  
  // Strip anything beyond 3 bytes for character as chat can't render it
  StripCharsByBytes(entity, sizeof entity);
  StripCharsByBytes(event, sizeof event);
  StripCharsByBytes(data, sizeof data);
  
  Action result;
  
  Call_StartForward(g_hEventReceiveForward);
  Call_PushStringEx(event, sizeof event, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_PushStringEx(data, sizeof data, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_Finish(result);
  
  if (result >= Plugin_Handled)
  {
    return;
  }
  
  char format[256];
  g_cEventFormat.GetString(format, sizeof format);
  
  if (strlen(format) > 0)
  {
    // Bound as %s arguments for the same reason as HandleChatMessage above --
    // event data could in principle also contain a literal '%'.
    CPrintToChatAll(format, entity, event, data);
  }
  else if (SupportsHexColor(g_evEngine))
  {
    CPrintToChatAll("{gold}[%s]{white}: {grey}%s", event, data);
  }
  else
  {
    CPrintToChatAll("\x10[%s]\x01: \x08%s", event, data);
  }
}

void HandleAuthResponse(JSONObject obj)
{
  bool success = obj.GetBool("success");
  
  if (!success)
  {
    char reason[128];
    
    if (!obj.GetString("reason", reason, sizeof reason))
    {
      strcopy(reason, sizeof reason, "no reason given");
    }
    
    SetFailState("Server denied our token: %s", reason);
    return;
  }
  
  LogMessage("Successfully authenticated");
  
  // If socket wasn't connected prior, do time check see if we are close to map start
  if (GetGameTime() <= 20.0 && g_cMapEvent.BoolValue)
  {
    char map[64];
    GetCurrentMap(map, sizeof map);
    DispatchEvent("Map Start", map);
  }
}

/**
 * Runs a server command relayed from an authorized Discord operator (see
 * /op and the "!"-prefixed command handler in scr-server), capturing its
 * printed output via ServerCommandEx() and relaying it back to the
 * originating Discord channel. Authorization is already enforced on the
 * relay server before this message is ever sent -- scr_allow_remote_commands
 * is a local kill switch on top of that, in case an admin wants to disable
 * remote execution on this server specifically without touching the relay's
 * operator list.
 */
void HandleCommandMessage(JSONObject obj)
{
  char command[MAX_COMMAND_LENGTH];
  char issuedBy[64];
  char replyTo[64];

  obj.GetString("command", command, sizeof command);
  obj.GetString("issuedBy", issuedBy, sizeof issuedBy);
  obj.GetString("replyTo", replyTo, sizeof replyTo);

  if (!g_cAllowRemoteCommands.BoolValue)
  {
    LogMessage("Ignored remote command from Discord user %s (scr_allow_remote_commands is disabled): %s", issuedBy, command);
    return;
  }

  if (strlen(command) == 0)
  {
    return;
  }

  Action result;

  Call_StartForward(g_hCommandReceiveForward);
  Call_PushStringEx(command, sizeof command, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_PushStringEx(issuedBy, sizeof issuedBy, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_Finish(result);

  if (result >= Plugin_Handled)
  {
    return;
  }

  char toRun[MAX_COMMAND_LENGTH];
  BuildExecutableCommand(command, toRun, sizeof toRun);

  if (strlen(toRun) == 0)
  {
    LogMessage("Ignored remote command from Discord user %s: %s (translated to nothing runnable)", issuedBy, command);

    if (strlen(replyTo) > 0)
    {
      SendToRelay(BuildCommandResponseMessage("(nothing to run)", replyTo));
    }

    return;
  }

  LogMessage("Executing remote command from Discord user %s: %s (as: %s)", issuedBy, command, toRun);

  char output[MAX_COMMAND_OUTPUT_LENGTH];
  ServerCommandEx(output, sizeof output, "%s", toRun);

  if (strlen(replyTo) > 0)
  {
    SendToRelay(BuildCommandResponseMessage(output, replyTo));
  }
}

/**
 * Returns the index of the first space or tab in command, or -1 if the
 * whole string is a single token. Discord messages should only ever
 * contain plain spaces, but this also tolerates tabs in case a command was
 * pasted in from somewhere else.
 */
int FindArgumentBoundary(const char[] command)
{
  int len = strlen(command);

  for (int i = 0; i < len; i++)
  {
    if (command[i] == ' ' || command[i] == '\t')
    {
      return i;
    }
  }

  return -1;
}

/**
 * Translates a "!"-issued Discord command the same way SourceMod's own
 * in-game chat triggers do: by default the first word gets an "sm_" prefix,
 * so a Discord operator sending "!kick 2 baduser" runs the same "sm_kick 2
 * baduser" admin command a player would trigger by typing "!kick 2
 * baduser" in chat -- rather than running a raw (and likely nonexistent)
 * "kick" console command. Chat triggers only apply this translation for
 * client-issued chat, not commands run directly on the server console,
 * which is the transport ServerCommandEx() uses here, so it has to be
 * done explicitly.
 *
 * A leading "rcon" word (e.g. "!rcon changelevel de_dust2") skips the
 * translation and runs the remainder exactly as given, for real console/
 * engine commands that aren't SourceMod admin commands. A command that
 * already starts with "sm_" is also left untouched, so it isn't double-
 * prefixed.
 *
 * A leading "sm_rcon" word is treated the same as "rcon", rather than being
 * left alone by the "already starts with sm_" rule above. SourceMod's own
 * sm_rcon handler runs its wrapped command with a plain ServerCommand()
 * instead of ServerCommandEx() when invoked from the server console (as
 * ServerCommandEx() does here), since it assumes a human is watching the
 * console directly and will see the output there. That means the wrapped
 * command's output would never reach our outer capture, and Discord would
 * see an empty response even though the command ran -- so "!sm_rcon foo"
 * is routed the same way "!rcon foo" is, straight to the raw command.
 */
void BuildExecutableCommand(const char[] command, char[] buffer, int maxlen)
{
  int boundary = FindArgumentBoundary(command);

  char firstWord[MAX_COMMAND_LENGTH];
  strcopy(firstWord, (boundary == -1) ? (strlen(command) + 1) : (boundary + 1), command);

  if (StrEqual(firstWord, "rcon", false) || StrEqual(firstWord, "sm_rcon", false))
  {
    if (boundary == -1)
    {
      // "rcon"/"sm_rcon" with nothing after it -- nothing to run.
      buffer[0] = '\0';
      return;
    }

    int rest = boundary;

    while (command[rest] == ' ' || command[rest] == '\t')
    {
      rest++;
    }

    strcopy(buffer, maxlen, command[rest]);
    return;
  }

  if (strncmp(command, "sm_", 3, false) == 0)
  {
    strcopy(buffer, maxlen, command);
    return;
  }

  if (boundary == -1)
  {
    Format(buffer, maxlen, "sm_%s", command);
    return;
  }

  Format(buffer, maxlen, "sm_%s%s", firstWord, command[boundary]);
}

public void Event_OnPlayerConnectionChange(Event event, const char[] name, bool dontBroadcast)
{
  bool isConnecting = StrEqual(name, "player_connect");
  
  int client;
  bool bot;
  
  if (isConnecting)
  {
    client = event.GetInt("index") + 1;
    bot = event.GetInt("bot") != 0;
  }
  else
  {
    int userid = event.GetInt("userid");
    client = GetClientOfUserId(userid);
    bot = event.GetInt("bot") != 0;
  }
  
  if (!IsValidClient(client, false) || !g_cPlayerEvent.BoolValue || (!g_cBotPlayerEvent.BoolValue && bot))
  {
    return;
  }
  
  char clientName[MAX_NAME_LENGTH];
  event.GetString("name", clientName, sizeof(clientName));
  
  if (clientName[0] == '\0')
  {
    LogMessage("Client has no name");
    return;
  }
  
  char eventType[32];
  Format(eventType, sizeof(eventType), "Player %s", isConnecting ? "Connected" : "Disconnected");
  DispatchEvent(eventType, clientName);
}

public void OnMapEnd()
{
  if (!g_cMapEvent.BoolValue)
  {
    return;
  }
  
  char map[64];
  GetCurrentMap(map, sizeof map);
  DispatchEvent("Map Ended", map);
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
  if (!IsValidClient(client))
  {
    return;
  }
  
  if (g_hWebSocket == null || !g_hWebSocket.Connected)
  {
    return;
  }
  
  if (StrEqual(g_sPrefix, ""))
  {
    DispatchMessage(client, sArgs);
  }
  else
  {
    if (g_bFlag && !CheckCommandAccess(client, "arandomcommandthatsnotregistered", g_iFlag, true))
    {
      return;
    }
    
    if (StrContains(sArgs, g_sPrefix) != 0)
    {
      return;
    }
    
    char buffer[MAX_COMMAND_LENGTH];
    
    for (int i = strlen(g_sPrefix); i < strlen(sArgs); i++)
    {
      Format(buffer, sizeof buffer, "%s%c", buffer, sArgs[i]);
    }
    
    DispatchMessage(client, buffer);
  }
}

void DispatchMessage(int client, const char[] sMessage)
{
  char id[64];
  char name[MAX_NAME_LENGTH];
  char message[MAX_COMMAND_LENGTH];
  
  Action result;
  
  strcopy(message, MAX_COMMAND_LENGTH, sMessage);
  
  if (!GetClientAuthId(client, AuthId_SteamID64, id, sizeof id))
  {
    return;
  }
  
  if (!GetClientName(client, name, sizeof name))
  {
    return;
  }
  
  Call_StartForward(g_hMessageSendForward);
  Call_PushCell(client);
  Call_PushStringEx(name, MAX_NAME_LENGTH, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_PushStringEx(message, MAX_COMMAND_LENGTH, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_Finish(result);
  
  if (result >= Plugin_Handled)
  {
    return;
  }
  
  SendToRelay(BuildChatMessage(IdentificationSteam, id, name, message));
}

/**
 * Fires SCR_OnEventSend and relays the event unless a plugin blocks it.
 *
 * This is the single path every event goes through, whether it originates
 * from scr's own built-in hooks (player connect/disconnect, map start/end)
 * or from a third-party plugin calling SCR_SendEvent. Neither has a
 * shortcut around the forward, so a companion plugin can observe or block
 * any event the same way regardless of who raised it.
 */
void DispatchEvent(const char[] event, const char[] data)
{
  char eventBuffer[MAX_EVENT_NAME_LENGTH];
  char dataBuffer[MAX_COMMAND_LENGTH];
  
  strcopy(eventBuffer, sizeof eventBuffer, event);
  strcopy(dataBuffer, sizeof dataBuffer, data);
  
  Action result;
  
  Call_StartForward(g_hEventSendForward);
  Call_PushStringEx(eventBuffer, sizeof eventBuffer, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_PushStringEx(dataBuffer, sizeof dataBuffer, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
  Call_Finish(result);
  
  if (result >= Plugin_Handled)
  {
    return;
  }
  
  SendToRelay(BuildEventMessage(eventBuffer, dataBuffer));
}

public any Native_SendMessage(Handle plugin, int numParams)
{
  if (numParams < 2)
  {
    return ThrowNativeError(SP_ERROR_NATIVE, "Insufficient parameters");
  }
  
  char buffer[512];
  int client = GetNativeCell(1);
  FormatNativeString(0, 2, 3, sizeof buffer, _, buffer);
  DispatchMessage(client, buffer);
  return 0;
}

public any Native_SendEvent(Handle plugin, int numParams)
{
  if (numParams < 2)
  {
    ThrowNativeError(SP_ERROR_NATIVE, "Insufficient parameters");
  }
  
  char event[MAX_EVENT_NAME_LENGTH];
  char data[MAX_COMMAND_LENGTH];
  
  GetNativeString(1, event, sizeof event);
  FormatNativeString(0, 2, 3, sizeof data, _, data);
  
  DispatchEvent(event, data);
  
  return 0;
}

void GenerateRandomChars(char[] buffer, int buffersize, int len)
{
  char charset[] = "adefghijstuv6789!@#$%^klmwxyz01bc2345nopqr&+=";
  
  for (int i = 0; i < len; i++)
  Format(buffer, buffersize, "%s%c", buffer, charset[GetRandomInt(0, sizeof charset - 1)]);
}

void StripCharsByBytes(char[] sBuffer, int iSize, int iMaxBytes = 3)
{
  int iBytes;
  
  char[] sClone = new char[iSize];
  
  int i = 0;
  int j = 0;
  int iBSize = 0;
  
  while (i < iSize)
  {
    iBytes = IsCharMB(sBuffer[i]);
    
    if (iBytes == 0)
      iBSize = 1;
    else
      iBSize = iBytes;
    
    if (iBytes <= iMaxBytes)
    {
      for (int k = 0; k < iBSize; k++)
      {
        sClone[j] = sBuffer[i + k];
        j++;
      }
    }
    
    i += iBSize;
  }
  
  Format(sBuffer, iSize, "%s", sClone);
}

int Server_GetPort()
{
  static ConVar cvHostport;
  
  if (cvHostport == null) {
    cvHostport = FindConVar("hostport");
  }
  
  if (cvHostport == null) {
    return 0;
  }
  
  int port = cvHostport.IntValue;
  
  return port;
}

bool IsValidClient(int client, bool checkConnected = true)
{
  if (client > 4096) {
    client = EntRefToEntIndex(client);
  }
  
  if (client < 1 || client > MaxClients) {
    return false;
  }
  
  if (checkConnected && !IsClientConnected(client)) {
    return false;
  }
  
  return true;
}

bool SupportsHexColor(EngineVersion e)
{
  switch (e)
  {
    case Engine_CSS, Engine_HL2DM, Engine_DODS, Engine_TF2, Engine_Insurgency, Engine_Unknown:
    {
      return true;
    }
    default:
    {
      return false;
    }
  }
}
