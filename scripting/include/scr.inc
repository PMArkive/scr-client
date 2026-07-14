#if defined _scr_included
#endinput
#endif
#define _scr_included

#if !defined MAX_EVENT_NAME_LENGTH
#define MAX_EVENT_NAME_LENGTH 128
#endif

#if !defined MAX_COMMAND_LENGTH
#define MAX_COMMAND_LENGTH 512
#endif

#if !defined MAX_COMMAND_OUTPUT_LENGTH
#define MAX_COMMAND_OUTPUT_LENGTH 2048
#endif

/**
 * Identification type of the unique ID accompanying a chat message.
 */
enum IdentificationType
{
  IdentificationInvalid = 0,
  IdentificationSteam,
  IdentificationDiscord,
  IdentificationTypeCount,
}

/**
 * Called upon sending a message via chat triggers
 * 
 * @param iClient 		Index of client that is sending the message
 * @param sClientName	Name of the client sending the message. The size of which is MAX_NAME_LENGTH
 * @param sMessage		Message content. The size of which is MAX_COMMAND_LENGTH
 */
forward Action SCR_OnMessageSend(int iClient, char[] sClientName, char[] sMessage);

/**
 * Called upon receiving a message
 * 
 * @param sEntityName	Entity name/hostname of the sending client
 * @param iIDType 		The IdentificationType of the ID
 * @param sID			String variant of the ID
 * @param sClientName	Name of the client that sent the message. The size of which is MAX_NAME_LENGTH
 * @param sMessage		Message content. The size of which is MAX_COMMAND_LENGTH
 */
forward Action SCR_OnMessageReceive(const char[] sEntityName, IdentificationType iIDType, const char[] sID, char[] sClientName, char[] sMessage);

/**
 * Called upon sending an event
 * 
 * @param sEvent		Name of the event. The size of which is MAX_EVENT_NAME_LENGTH
 * @param sData			Data of the event. The size of which is MAX_COMMAND_LENGTH
 */
forward Action SCR_OnEventSend(char[] sEvent, char[] sData);

/**
 * Called upon receiving an event
 * 
 * @param sEvent		Name of the event. The size of which is MAX_EVENT_NAME_LENGTH
 * @param sData			Data of the event. The size of which is MAX_COMMAND_LENGTH
 */
forward Action SCR_OnEventReceive(char[] sEvent, char[] sData);

/**
 * Called upon receiving a remote server command from an authorized Discord
 * operator (see /op in scr-server). Return Plugin_Handled or higher to
 * block the command from being executed with ServerCommand().
 * 
 * @param sCommand		The command to be executed. The size of which is MAX_COMMAND_LENGTH
 * @param sIssuedBy		Discord user id of the operator who issued the command. The size of which is 64
 */
forward Action SCR_OnCommandReceive(char[] sCommand, char[] sIssuedBy);

/**
 * Sends a message to the router
 * 
 * @param iClient   Client ID to use as name display (If left at 0, it will display "CONSOLE")
 * @param fmt       Format string
 * @param ...       Format arguments
 */
native void SCR_SendMessage(int iClient = 0, const char[] fmt, any...);

/**
 * Sends an event to the router
 * 
 * @param sEvent	Name of the event
 * @param sData		Data format string
 * @param ...		Format arguments
 */
native void SCR_SendEvent(const char[] sEvent, const char[] sData, any...);

#if !defined REQUIRE_PLUGIN
public __pl_scr_SetNTVOptional()
{
  MarkNativeAsOptional("SCR_SendMessage");
  MarkNativeAsOptional("SCR_SendEvent");
}
#endif

public SharedPlugin __pl_scr = 
{
  name = "scr", 
  file = "scr.smx", 
  #if defined REQUIRE_PLUGIN
  required = 1, 
  #else
  required = 0, 
  #endif
};
