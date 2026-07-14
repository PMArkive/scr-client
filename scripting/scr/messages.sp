/**
 * Converts an IdentificationType to its wire (JSON) string form.
 */
stock void IdTypeToString(IdentificationType idType, char[] buffer, int maxlength)
{
  switch (idType)
  {
    case IdentificationSteam: strcopy(buffer, maxlength, "steam");
    case IdentificationDiscord: strcopy(buffer, maxlength, "discord");
    default: strcopy(buffer, maxlength, "unknown");
  }
}

/**
 * Converts a wire (JSON) idType string back to an IdentificationType.
 */
stock IdentificationType StringToIdType(const char[] value)
{
  if (StrEqual(value, "steam"))
  {
    return IdentificationSteam;
  }

  if (StrEqual(value, "discord"))
  {
    return IdentificationDiscord;
  }

  return IdentificationInvalid;
}

/**
 * Builds an {type: "authenticate", token} message.
 *
 * @note Returned JSONObject must be passed to SendToRelay, which serializes it
 * with JSONObject.ToString and sends it via WebSocket.WriteString, then frees it.
 */
stock JSONObject BuildAuthenticateMessage(const char[] token)
{
  JSONObject obj = new JSONObject();

  obj.SetString("type", "authenticate");
  obj.SetString("token", token);

  return obj;
}

/**
 * Builds a {type: "chat", entityName, idType, id, username, message} message.
 *
 * @note entityName is taken from the global g_sHostname, matching the old
 * BaseMessage.WriteEntityName() behavior.
 * @note Returned JSONObject must be passed to SendToRelay, which serializes it
 * with JSONObject.ToString and sends it via WebSocket.WriteString, then frees it.
 */
stock JSONObject BuildChatMessage(IdentificationType idType, const char[] id, const char[] username, const char[] message)
{
  char sIdType[16];
  IdTypeToString(idType, sIdType, sizeof sIdType);

  JSONObject obj = new JSONObject();

  obj.SetString("type", "chat");
  obj.SetString("entityName", g_sHostname);
  obj.SetString("idType", sIdType);
  obj.SetString("id", id);
  obj.SetString("username", username);
  obj.SetString("message", message);

  return obj;
}

/**
 * Builds a {type: "event", entityName, event, data} message.
 *
 * @note entityName is taken from the global g_sHostname, matching the old
 * BaseMessage.WriteEntityName() behavior.
 * @note Returned JSONObject must be passed to SendToRelay, which serializes it
 * with JSONObject.ToString and sends it via WebSocket.WriteString, then frees it.
 */
stock JSONObject BuildEventMessage(const char[] event, const char[] data)
{
  JSONObject obj = new JSONObject();

  obj.SetString("type", "event");
  obj.SetString("entityName", g_sHostname);
  obj.SetString("event", event);
  obj.SetString("data", data);

  return obj;
}

/**
 * Builds a {type: "commandResponse", output, replyTo} message.
 *
 * Sent back after executing a remote command received via a "command"
 * message, carrying the console output captured by ServerCommandEx() and
 * the Discord channel node id to deliver it to.
 *
 * @note Returned JSONObject must be passed to SendToRelay, which serializes it
 * with JSONObject.ToString and sends it via WebSocket.WriteString, then frees it.
 */
stock JSONObject BuildCommandResponseMessage(const char[] output, const char[] replyTo)
{
  JSONObject obj = new JSONObject();

  obj.SetString("type", "commandResponse");
  obj.SetString("output", output);
  obj.SetString("replyTo", replyTo);

  return obj;
}
