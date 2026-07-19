/**
 * CommandBox / MiniServer WebSocket listener for the CBWIRE test harness.
 * Requires SocketBox. Uses the Core listener (no STOMP).
 * For STOMP + CBWIRE on the same endpoint, extend CBWIREWebSocketStomp instead.
 */
component extends="cbwire.models.websocket.CBWIREWebSocket" {
}
