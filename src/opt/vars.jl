const errorMsg = "Fatal websocket error"

const CONTINUATION_FRAME = 0x00
const TEXT_FRAME = 0x01
const BINARY_FRAME = 0x02
const CONNECTION_CLOSE_FRAME = 0x08
const PING_FRAME = 0x09
const PONG_FRAME = 0x0a

const WS_FINAL = 0x80
const WS_OPCODE = 0x0F
const WS_MASK = 0x80
const WS_LENGTH = 0x7F
const WS_RSV1 = 0x40
const WS_RSV2 = 0x20
const WS_RSV3 = 0x10

const DECODE_HEADER = 1
const WAITING_FOR_16_BIT_LENGTH = 2
const WAITING_FOR_64_BIT_LENGTH = 3
const WAITING_FOR_MASK_KEY = 4
const WAITING_FOR_PAYLOAD = 5
const COMPLETE = 6

const CLOSE_REASON_NORMAL = 1000
const CLOSE_REASON_GOING_AWAY = 1001
const CLOSE_REASON_PROTOCOL_ERROR = 1002
const CLOSE_REASON_UNPROCESSABLE_INPUT = 1003
const CLOSE_REASON_RESERVED = 1004              #Reserved value.  Undefined meaning.
const CLOSE_REASON_NOT_PROVIDED = 1005          #Not to be used on the wire
const CLOSE_REASON_ABNORMAL = 1006              #Not to be used on the wire
const CLOSE_REASON_INVALID_DATA = 1007
const CLOSE_REASON_POLICY_VIOLATION = 1008
const CLOSE_REASON_MESSAGE_TOO_BIG = 1009
const CLOSE_REASON_EXTENSION_REQUIRED = 1010
const CLOSE_REASON_INTERNAL_SERVER_ERROR = 1011
const CLOSE_REASON_TLS_HANDSHAKE_FAILED = 1015
const CLOSE_DESCRIPTIONS = Dict{Int, String}(
    1000 => "Normal connection closure",
    1001 => "Remote peer is going away",
    1002 => "Protocol error",
    1003 => "Unprocessable input",
    1004 => "Reserved",
    1005 => "Reason not provided",
    1006 => "Abnormal closure, no further detail available",
    1007 => "Invalid data received",
    1008 => "Policy violation",
    1009 => "Message too big",
    1010 => "Extension requested by client is required",
    1011 => "Internal Server Error",
    1015 => "TLS Handshake Failed"
)

# Connected, fully-open, ready to send and receive frames
const STATE_OPEN = "open"
# Received a close frame from the remote peer
const STATE_PEER_REQUESTED_CLOSE = "peer_requested_close"
# Sent close frame to remote peer.  No further data can be sent.
const STATE_ENDING = "ending"
# Connection is fully closed.  No further data can be sent or received.
const STATE_CLOSED = "closed"

const defaultConfig = (
    # 1MiB max frame size.
    maxReceivedFrameSize = 0x100000,
    # 8MiB max message size, only applicable if
    # assembleFragments is true
    maxReceivedMessageSize = 0x800000,
    # Outgoing messages larger than fragmentationThreshold will be
    # split into multiple fragments.
    fragmentOutgoingMessages = true,
    # Outgoing frames are fragmented if they exceed this threshold.
    # Default is 16KiB
    fragmentationThreshold = 0x4000,
    # If true, fragmented messages will be automatically assembled
    # and the full message will be emitted via a 'message' event.
    # If false, each frame will be emitted via a 'frame' event and
    # the application will be responsible for aggregating multiple
    # fragmented frames.  Single-frame messages will emit a 'message'
    # event in addition to the 'frame' event.
    # Most users will want to leave this set to 'true'
    assembleFragments = true,
    # The number of seconds to wait after sending a close frame
    # for an acknowledgement to come back before giving up and just
    # closing the socket.
    closeTimeout = 5,
)

