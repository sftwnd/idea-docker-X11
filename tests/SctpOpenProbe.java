import com.sun.nio.sctp.SctpServerChannel;
public class SctpOpenProbe {
    public static void main(String[] a) {
        try { SctpServerChannel ssc = SctpServerChannel.open(); ssc.close(); System.out.println("OPEN_OK"); }
        catch (UnsupportedOperationException e) { System.out.println("UOE_OK:" + e.getMessage()); }
        catch (Throwable t) { System.out.println("OTHER:" + t.getClass().getName() + ":" + t.getMessage()); }
    }
}
