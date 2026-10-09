package com.aichat.server.llm;

import com.aichat.server.auth.CurrentDevice;
import com.aichat.server.auth.SimpleRateLimiter;
import com.aichat.server.common.*;
import com.aichat.server.config.AppProperties;
import com.aichat.server.llm.ModelAdapter.CompletionRequest;
import jakarta.annotation.PreDestroy;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api")
public class LlmController {
    private final ModelRouter router;
    private final LlmRelayService relay;
    private final AppProperties app;
    private final LlmProperties properties;
    private final SimpleRateLimiter limiter;
    private final ExecutorService workers=Executors.newVirtualThreadPerTaskExecutor();
    private final ScheduledExecutorService timers=Executors.newScheduledThreadPool(1);
    private final Semaphore slots=new Semaphore(16);
    public LlmController(ModelRouter router,LlmRelayService relay,AppProperties app,LlmProperties properties,SimpleRateLimiter limiter){
        this.router=router;this.relay=relay;this.app=app;this.properties=properties;this.limiter=limiter;
    }
    @GetMapping("/models")
    public ApiResponse<?> models(HttpServletRequest req){return new ApiResponse<>(router.catalog(),RequestIdFilter.from(req));}
    @PostMapping("/llm/completions")
    public Object complete(@RequestBody CompletionRequest request,
        @RequestHeader(value="X-Provider-Key",required=false) String credential,HttpServletRequest req){
        if(!app.getFeatures().isLlmRelay())throw error(HttpStatus.FORBIDDEN,"FEATURE_DISABLED","LLM 中继未启用");
        Object value=req.getAttribute(CurrentDevice.REQUEST_ATTRIBUTE);
        if(!(value instanceof CurrentDevice device))throw error(HttpStatus.UNAUTHORIZED,"AUTH_REQUIRED","需要设备令牌");
        boolean local=java.util.Set.of("127.0.0.1","::1","0:0:0:0:0:0:0:1").contains(req.getRemoteAddr());
        if(!req.isSecure()&&!(properties.isAllowLocalHttp()&&local))throw error(HttpStatus.FORBIDDEN,"HTTPS_REQUIRED","中继请求需要 HTTPS");
        limiter.check("llm:"+device.id(),30,60);
        router.select(request);
        if(!slots.tryAcquire())throw error(HttpStatus.TOO_MANY_REQUESTS,"RATE_LIMITED","服务器中继并发已满");
        String requestId=RequestIdFilter.from(req);
        var cancellation=new LlmRelayService.Cancellation();
        long timeout=Math.max(1,Math.min(120,properties.getTimeoutSeconds()));
        if(!request.stream()){
            var timer=timers.schedule(cancellation::close,timeout,TimeUnit.SECONDS);
            try{return new ApiResponse<>(relay.complete(request,credential,requestId,cancellation,(type,data)->{}),requestId);}
            finally{timer.cancel(false);cancellation.close();slots.release();}
        }
        var emitter=new SseEmitter((timeout+2)*1000);
        var ended=new AtomicBoolean();
        Runnable cancel=()->{ended.set(true);cancellation.close();};
        emitter.onCompletion(cancel);emitter.onError(error->cancel.run());emitter.onTimeout(cancel);
        var timer=timers.schedule(()->{
            if(ended.compareAndSet(false,true)){
                try{emitter.send(SseEmitter.event().name("error").data(Map.of("code","PROVIDER_TIMEOUT","message","供应商请求超时","requestId",requestId)));}
                catch(Exception ignored){}
                cancellation.close();emitter.complete();
            }
        },timeout,TimeUnit.SECONDS);
        var heartbeat=timers.scheduleAtFixedRate(()->{
            if(!ended.get())try{emitter.send(SseEmitter.event().comment("heartbeat"));}catch(Exception e){cancel.run();}
        },10,10,TimeUnit.SECONDS);
        workers.submit(()->{
            try{
                var result=relay.complete(request,credential,requestId,cancellation,(type,data)->{
                    cancellation.check();
                    if(!ended.get())emitter.send(SseEmitter.event().name(type).data(data));
                });
                if(ended.compareAndSet(false,true)){
                    emitter.send(SseEmitter.event().name("done").data(Map.of("finishReason",result.finishReason())));
                    emitter.complete();
                }
            }catch(Exception failure){
                if(ended.compareAndSet(false,true)){
                    ApiException api=failure instanceof ApiException e?e:error(HttpStatus.BAD_GATEWAY,"PROVIDER_BAD_RESPONSE","中继请求失败");
                    Map<String,Object> data=new java.util.LinkedHashMap<>();data.put("code",api.getCode());data.put("message",api.getMessage());data.put("requestId",requestId);
                    if(api.getRetryAfterSeconds()!=null)data.put("retryAfterSeconds",api.getRetryAfterSeconds());
                    try{emitter.send(SseEmitter.event().name("error").data(data));}catch(Exception ignored){}
                    emitter.complete();
                }
            }finally{timer.cancel(false);heartbeat.cancel(false);cancellation.close();slots.release();}
        });
        return emitter;
    }
    @PreDestroy void shutdown(){workers.shutdownNow();timers.shutdownNow();}
    private ApiException error(HttpStatus status,String code,String message){return new ApiException(status,code,message);}
}
