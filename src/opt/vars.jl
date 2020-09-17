const errorMsg = "Fatal websocket error"

const CONTINUATION_FRAME = UInt8(0)
const TEXT_FRAME = UInt8(1)
const BINARY_FRAME = UInt8(2)
const CONNECTION_CLOSE_FRAME = UInt8(8)
const PING_FRAME = UInt8(9)
const PONG_FRAME = UInt8(10)

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
    # Which version of the protocol to use for this session.  This
    # option will be removed once the protocol is finalized by the IETF
    # It is only available to ease the transition through the
    # intermediate draft protocol versions.
    # At present, it only affects the name of the Origin header.
    webSocketVersion = 13,
    # If true, fragmented messages will be automatically assembled
    # and the full message will be emitted via a 'message' event.
    # If false, each frame will be emitted via a 'frame' event and
    # the application will be responsible for aggregating multiple
    # fragmented frames.  Single-frame messages will emit a 'message'
    # event in addition to the 'frame' event.
    # Most users will want to leave this set to 'true'
    assembleFragments = true,
    # The Nagle Algorithm makes more efficient use of network resources
    # by introducing a small delay before sending small packets so that
    # multiple messages can be batched together before going onto the
    # wire.  This however comes at the cost of latency, so the default
    # is to disable it.  If you don't need low latency and are streaming
    # lots of small messages, you can change this to 'false'
    disableNagleAlgorithm = true,
    # The number of seconds to wait after sending a close frame
    # for an acknowledgement to come back before giving up and just
    # closing the socket.
    closeTimeout = 5,
    # Options to pass to https.connect if connecting via TLS
    tlsOptions = NamedTuple()
)

