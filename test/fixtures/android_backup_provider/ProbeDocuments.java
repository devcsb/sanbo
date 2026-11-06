package com.sanbo.qa.documents;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

/** Synthetic provider installed ONLY on the ephemeral QA emulator. */
public class ProbeDocuments extends DocumentsProvider {
  private static final String[] DOC = {Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_SIZE, Document.COLUMN_FLAGS};
  public boolean onCreate() { return true; }
  public Cursor queryRoots(String[] projection) {
    MatrixCursor c = new MatrixCursor(new String[]{Root.COLUMN_ROOT_ID,Root.COLUMN_DOCUMENT_ID,Root.COLUMN_TITLE,Root.COLUMN_FLAGS,Root.COLUMN_MIME_TYPES});
    c.addRow(new Object[]{"qa","root","산보 보안 QA",0,"application/octet-stream"});return c;
  }
  private void add(MatrixCursor c, String id) {
    boolean dir=id.equals("root");
    c.addRow(new Object[]{id,dir?"QA":id+".sanbo",dir?Document.MIME_TYPE_DIR:"application/octet-stream",id.equals("huge")?1L:null,0});
  }
  public Cursor queryDocument(String id,String[] projection) { if(id.equals("blocked") && "com.sanbo.sanbo".equals(getCallingPackage())) { try { Thread.sleep(6000); } catch(InterruptedException e) { Thread.currentThread().interrupt(); } } MatrixCursor c=new MatrixCursor(DOC);add(c,id);return c; }
  public Cursor queryChildDocuments(String parent,String[] projection,String order) { MatrixCursor c=new MatrixCursor(DOC);for(String id:new String[]{"normal","unknown","huge","slow","maximum","failed","blocked"})add(c,id);return c; }
  public ParcelFileDescriptor openDocument(String id,String mode,CancellationSignal signal) throws FileNotFoundException {
    if(!mode.equals("r"))throw new FileNotFoundException();
    try {
      ParcelFileDescriptor[] pipe=ParcelFileDescriptor.createReliablePipe();
      AtomicBoolean cancelled=new AtomicBoolean(false);
      if(signal!=null)signal.setOnCancelListener(()->cancelled.set(true));
      new Thread(()->{
        String json="{\"export_kind\":\"sanbo_backup\",\"backup_schema_version\":2,\"database_schema_version\":6,\"exported_at\":\"2026-11-07T00:00:00Z\",\"tables\":{\"sessions\":[{\"id\":\"qa-"+id+"\",\"started_at\":\"2026-11-07T00:00:00Z\",\"ended_at\":\"2026-11-07T00:01:00Z\",\"timezone\":\"UTC\",\"status\":\"completed\",\"tracking_mode\":\"balanced\",\"duration_s\":60,\"moving_time_s\":40,\"stationary_time_s\":20,\"total_distance_m\":10}],\"location_samples\":[],\"minute_windows\":[],\"places\":[],\"route_exclusions\":[]}}";
        try(ParcelFileDescriptor.AutoCloseOutputStream out=new ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])) {
          byte[] prefix=json.getBytes(StandardCharsets.UTF_8);out.write(prefix);out.flush();
          if(id.equals("failed")) { pipe[1].closeWithError("synthetic-provider-failure"); return; }
          if(id.equals("slow")) {for(int i=0;i<60&&!cancelled.get();i++){Thread.sleep(1000);out.write(' ');out.flush();}}
          if(id.equals("huge")||id.equals("maximum")) {
            long left=50L*1024*1024+(id.equals("huge")?1:0)-prefix.length;
            byte[] spaces=new byte[8192];java.util.Arrays.fill(spaces,(byte)' ');
            while(left>0&&!cancelled.get()){int n=(int)Math.min(left,spaces.length);out.write(spaces,0,n);left-=n;}
          }
        } catch(Exception ignored) { }
      },"qa-documents").start();
      return pipe[0];
    } catch(IOException error) {throw new FileNotFoundException(error.toString());}
  }
}
