import com.sun.nio.sctp.*;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

public class SctpLoopback {
    static final String MSG = "SCTP-CANON-OK";
    static final AbstractNotificationHandler<Object> CONT = new AbstractNotificationHandler<>() {
        @Override public HandlerResult handleNotification(Notification n, Object att) { return HandlerResult.CONTINUE; }
    };
    static byte[] recvData(SctpChannel ch) throws Exception {
        ByteBuffer buf = ByteBuffer.allocateDirect(4096);
        for (int i = 0; i < 50; i++) {
            buf.clear();
            MessageInfo mi = ch.receive(buf, null, CONT);
            if (mi != null && buf.position() > 0) { buf.flip(); byte[] b = new byte[buf.remaining()]; buf.get(b); return b; }
        }
        throw new IllegalStateException("no data received");
    }
    public static void main(String[] a) throws Exception {
        try (SctpServerChannel ssc = SctpServerChannel.open()) {
            ssc.bind(new InetSocketAddress("127.0.0.1", 0));
            int port = ((InetSocketAddress) ssc.getAllLocalAddresses().iterator().next()).getPort();
            Thread srv = new Thread(() -> {
                try (SctpChannel peer = ssc.accept()) {
                    byte[] got = recvData(peer);
                    peer.send(ByteBuffer.wrap(got), MessageInfo.createOutgoing(null, 0));
                } catch (Exception e) { e.printStackTrace(); }
            });
            srv.setDaemon(true); srv.start();
            try (SctpChannel sc = SctpChannel.open(new InetSocketAddress("127.0.0.1", port), 0, 0)) {
                sc.send(ByteBuffer.wrap(MSG.getBytes(StandardCharsets.UTF_8)), MessageInfo.createOutgoing(null, 0));
                String s = new String(recvData(sc), StandardCharsets.UTF_8);
                if (!MSG.equals(s)) { System.out.println("ASSOC_RC=1 mismatch=[" + s + "]"); System.exit(1); }
                System.out.println("ASSOC_RC=0 echo=[" + s + "]");
            }
        }
    }
}
