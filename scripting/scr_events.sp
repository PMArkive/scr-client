#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <scr>

#define PLUGIN_VERSION "1.0"

public Plugin myinfo =
{
  name = "SCR ANSI Events",
  author = "ampere",
  description = "Companion plugin: sends ANSI-colored connect/disconnect/map/moderation events to Discord through scr",
  version = PLUGIN_VERSION,
  url = "https://github.com/maxijabase"
};

#define ANSI_RESET  "\x1B[0m"
#define ANSI_GREEN  "\x1B[1;32m"
#define ANSI_RED    "\x1B[1;31m"
#define ANSI_YELLOW "\x1B[1;33m"
#define ANSI_CYAN   "\x1B[1;36m"
#define ANSI_BLUE   "\x1B[1;34m"
#define ANSI_PINK   "\x1B[1;35m"

/**
 * Set while this plugin is re-emitting a built-in event with its own
 * formatting, so its own SCR_OnEventSend hook doesn't intercept the
 * re-emission and recurse into itself.
 */
bool g_bReplacingBuiltinEvent;

public void OnPluginStart()
{
  AddCommandListener(Listener_Kick, "sm_kick");
  AddCommandListener(Listener_Ban, "sm_ban");
  AddCommandListener(Listener_Mute, "sm_mute");
  AddCommandListener(Listener_Gag, "sm_gag");
  AddCommandListener(Listener_Silence, "sm_silence");
}

/**
 * Replaces the plain text of scr's own built-in connect/disconnect/map
 * events with an ANSI-colored version. Requires scr_event_player and/or
 * scr_event_map to stay enabled -- this only reformats what scr already
 * emits, it doesn't independently hook the underlying game events.
 */
public Action SCR_OnEventSend(char[] event, char[] data)
{
  if (g_bReplacingBuiltinEvent)
  {
    return Plugin_Continue;
  }

  char replacement[512];

  if (StrEqual(event, "Player Connected"))
  {
    Format(replacement, sizeof replacement, "%s+ %s connected%s", ANSI_GREEN, data, ANSI_RESET);
  }
  else if (StrEqual(event, "Player Disconnected"))
  {
    Format(replacement, sizeof replacement, "%s- %s disconnected%s", ANSI_RED, data, ANSI_RESET);
  }
  else if (StrEqual(event, "Map Start"))
  {
    Format(replacement, sizeof replacement, "%s🗺️ map start: %s%s", ANSI_YELLOW, data, ANSI_RESET);
  }
  else if (StrEqual(event, "Map Ended"))
  {
    Format(replacement, sizeof replacement, "%s🏁 map ended: %s%s", ANSI_YELLOW, data, ANSI_RESET);
  }
  else
  {
    return Plugin_Continue;
  }

  g_bReplacingBuiltinEvent = true;
  SCR_SendEvent(event, "%s", replacement);
  g_bReplacingBuiltinEvent = false;

  return Plugin_Handled;
}

public Action Listener_Kick(int client, const char[] command, int argc)
{
  #pragma unused command

  if (argc < 1)
  {
    return Plugin_Continue;
  }

  char targetPattern[65];
  GetCmdArg(1, targetPattern, sizeof targetPattern);

  char reason[192];
  GetJoinedArgs(2, argc, reason, sizeof reason);

  NotifyModerationTargets(targetPattern, client, "Player Kicked", "👢", ANSI_YELLOW, "kicked", "", reason);
  return Plugin_Continue;
}

public Action Listener_Ban(int client, const char[] command, int argc)
{
  #pragma unused command

  if (argc < 2)
  {
    return Plugin_Continue;
  }

  char targetPattern[65];
  GetCmdArg(1, targetPattern, sizeof targetPattern);

  char minutesArg[16];
  GetCmdArg(2, minutesArg, sizeof minutesArg);
  int minutes = StringToInt(minutesArg);

  char reason[192];
  GetJoinedArgs(3, argc, reason, sizeof reason);

  char duration[32];

  if (minutes <= 0)
  {
    strcopy(duration, sizeof duration, "permanently");
  }
  else
  {
    Format(duration, sizeof duration, "for %d minute%s", minutes, minutes == 1 ? "" : "s");
  }

  NotifyModerationTargets(targetPattern, client, "Player Banned", "🔨", ANSI_RED, "banned", duration, reason);
  return Plugin_Continue;
}

public Action Listener_Mute(int client, const char[] command, int argc)
{
  #pragma unused command

  if (argc < 1)
  {
    return Plugin_Continue;
  }

  char targetPattern[65];
  GetCmdArg(1, targetPattern, sizeof targetPattern);

  NotifyModerationTargets(targetPattern, client, "Player Muted", "🔇", ANSI_CYAN, "muted", "", "");
  return Plugin_Continue;
}

public Action Listener_Gag(int client, const char[] command, int argc)
{
  #pragma unused command

  if (argc < 1)
  {
    return Plugin_Continue;
  }

  char targetPattern[65];
  GetCmdArg(1, targetPattern, sizeof targetPattern);

  NotifyModerationTargets(targetPattern, client, "Player Gagged", "🤐", ANSI_BLUE, "gagged", "", "");
  return Plugin_Continue;
}

public Action Listener_Silence(int client, const char[] command, int argc)
{
  #pragma unused command

  if (argc < 1)
  {
    return Plugin_Continue;
  }

  char targetPattern[65];
  GetCmdArg(1, targetPattern, sizeof targetPattern);

  NotifyModerationTargets(targetPattern, client, "Player Silenced", "🔕", ANSI_PINK, "silenced", "", "");
  return Plugin_Continue;
}

/**
 * Resolves targetPattern (as accepted by the admin command itself, e.g.
 * "#7", a partial name, or "@all") and sends one ANSI-formatted event per
 * resolved target.
 *
 * @note Runs before the underlying admin command actually executes, so it
 * reports intent, not confirmed success -- a failed ban (bad immunity,
 * no match, etc.) can still produce a log line here.
 */
void NotifyModerationTargets(
  const char[] targetPattern,
  int admin,
  const char[] eventName,
  const char[] emoji,
  const char[] color,
  const char[] verb,
  const char[] duration,
  const char[] reason)
{
  char targetName[MAX_TARGET_LENGTH];
  bool tnIsMl;
  int targets[MAXPLAYERS + 1];

  int targetCount = ProcessTargetString(
    targetPattern,
    admin,
    targets,
    MAXPLAYERS,
    COMMAND_FILTER_NO_IMMUNITY,
    targetName,
    sizeof targetName,
    tnIsMl);

  if (targetCount <= 0)
  {
    return;
  }

  char adminName[MAX_NAME_LENGTH];

  if (admin == 0)
  {
    strcopy(adminName, sizeof adminName, "Console");
  }
  else
  {
    GetClientName(admin, adminName, sizeof adminName);
  }

  for (int i = 0; i < targetCount; i++)
  {
    char clientName[MAX_NAME_LENGTH];
    GetClientName(targets[i], clientName, sizeof clientName);

    char durationSuffix[40];
    durationSuffix[0] = '\0';

    if (duration[0] != '\0')
    {
      Format(durationSuffix, sizeof durationSuffix, " %s", duration);
    }

    char reasonSuffix[224];
    reasonSuffix[0] = '\0';

    if (reason[0] != '\0')
    {
      Format(reasonSuffix, sizeof reasonSuffix, " (%s)", reason);
    }

    char text[512];
    Format(text, sizeof text, "%s%s %s %s %s%s%s%s",
      color, emoji, adminName, verb, clientName, durationSuffix, reasonSuffix, ANSI_RESET);

    SCR_SendEvent(eventName, "%s", text);
  }
}

/** Joins command args [startArg, argc] with single spaces into buffer. */
void GetJoinedArgs(int startArg, int argc, char[] buffer, int size)
{
  buffer[0] = '\0';

  char part[192];

  for (int i = startArg; i <= argc; i++)
  {
    GetCmdArg(i, part, sizeof part);

    if (buffer[0] != '\0')
    {
      Format(buffer, size, "%s %s", buffer, part);
    }
    else
    {
      strcopy(buffer, size, part);
    }
  }
}
