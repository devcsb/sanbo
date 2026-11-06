package com.sanbo.qa.documents;
import android.app.Activity;
import android.app.Application;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.Bundle;
import java.io.File;
import java.util.concurrent.atomic.AtomicInteger;
public class LifecycleProbe extends Instrumentation {
  private boolean checkBusy;
  public void onCreate(Bundle arguments) {super.onCreate(arguments);checkBusy=arguments!=null && "blocked".equals(arguments.getString("mode"));start();}
  public void onStart() {
    java.util.concurrent.atomic.AtomicReference<Activity> latest=new java.util.concurrent.atomic.AtomicReference<>();
    java.util.concurrent.atomic.AtomicReference<Activity> first=new java.util.concurrent.atomic.AtomicReference<>();
    AtomicInteger created=new AtomicInteger(), destroyed=new AtomicInteger(), resumed=new AtomicInteger();
    try {
      Application application=(Application)getTargetContext().getApplicationContext();
      application.registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks(){
        public void onActivityCreated(Activity a,Bundle b){if(a.getClass().getName().equals("com.sanbo.sanbo.MainActivity")){created.incrementAndGet();first.compareAndSet(null,a);latest.set(a);}}
        public void onActivityDestroyed(Activity a){if(a.getClass().getName().equals("com.sanbo.sanbo.MainActivity"))destroyed.incrementAndGet();}
        public void onActivityResumed(Activity a){if(a.getClass().getName().equals("com.sanbo.sanbo.MainActivity"))resumed.incrementAndGet();}
        public void onActivityStarted(Activity a){} public void onActivityPaused(Activity a){}
        public void onActivityStopped(Activity a){} public void onActivitySaveInstanceState(Activity a,Bundle b){}
      });
      runOnMainSync(()->getTargetContext().startActivity(new Intent().setClassName("com.sanbo.sanbo","com.sanbo.sanbo.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK)));
      long launchLimit=System.currentTimeMillis()+15000;
      while(first.get()==null && System.currentTimeMillis()<launchLimit)Thread.sleep(100);
      Activity initial=first.get();
      if(initial==null)throw new Exception("activity-not-created");
      Bundle ready=new Bundle();ready.putString("phase",(checkBusy?"choose blocked.sanbo within 90 seconds":"choose slow.sanbo within 90 seconds"));sendStatus(0,ready);
      File root=new File(getTargetContext().getCacheDir(),"sanbo_imports");
      long limit=System.currentTimeMillis()+90000;
      while(System.currentTimeMillis()<limit && (resumed.get()<2 || count(root)==0))Thread.sleep(100);
      if(resumed.get()<2 || count(root)==0)throw new Exception("read-not-started");
      Thread.sleep(500);
      runOnMainSync(()->initial.recreate());
      java.util.concurrent.atomic.AtomicReference<String> busyCode=new java.util.concurrent.atomic.AtomicReference<>();
      if(checkBusy) {
        long nextLimit=System.currentTimeMillis()+3000;
        while(created.get()<2 && System.currentTimeMillis()<nextLimit)Thread.sleep(10);
        runOnMainSync(()->{
          try {
            java.lang.reflect.Field field=initial.getClass().getDeclaredField("backupImportHandler");field.setAccessible(true);
            // Find the newly resumed Activity through the lifecycle observer.
            Activity current=latest.get();
            Object handler=field.get(current);
            Class<?> callback=Class.forName("io.flutter.plugin.common.MethodChannel$Result");
            Object result=java.lang.reflect.Proxy.newProxyInstance(callback.getClassLoader(),new Class<?>[]{callback},(proxy,method,args)->{if(method.getName().equals("error"))busyCode.set((String)args[0]);return null;});
            java.lang.reflect.Method pick=handler.getClass().getDeclaredMethod("pick",String.class,callback);pick.setAccessible(true);pick.invoke(handler,"qa-overlap",result);
            if(!"import_busy".equals(busyCode.get())) {java.lang.reflect.Method close=handler.getClass().getDeclaredMethod("close");close.invoke(handler);}
          } catch(Exception error){busyCode.set(error.toString());}
        });
      }
      limit=System.currentTimeMillis()+15000;
      while(System.currentTimeMillis()<limit && (created.get()<2 || destroyed.get()<1 || count(root)!=0))Thread.sleep(100);
      Bundle result=new Bundle();result.putInt("created",created.get());result.putInt("destroyed",destroyed.get());result.putInt("cacheFiles",count(root));
      boolean ok=created.get()>=2 && destroyed.get()>=1 && count(root)==0 && (!checkBusy || "import_busy".equals(busyCode.get()));
      result.putString("overlap",String.valueOf(busyCode.get()));
      result.putString("phase",ok?"PASS":"FAIL");finish(ok?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
    } catch(Exception e) {Bundle error=new Bundle();error.putString("error",e.toString());finish(Activity.RESULT_CANCELED,error);}
  }
  private int count(File root){File[] files=root.listFiles((d,name)->name.startsWith("import-"));return files==null?0:files.length;}
}
