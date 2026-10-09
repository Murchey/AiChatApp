package com.aichat.server.common;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** Bound chunked as well as Content-Length JSON before deserializing arrays. */
@Component
@Order(1)
public class JsonBodyLimitFilter extends OncePerRequestFilter {
    public static final int LIMIT=4*1024*1024;
    private final ObjectMapper mapper;
    public JsonBodyLimitFilter(ObjectMapper mapper){this.mapper=mapper;}
    @Override protected boolean shouldNotFilter(HttpServletRequest request){
        return !request.getRequestURI().startsWith("/api/")||!java.util.Set.of("POST","PUT","PATCH").contains(request.getMethod());
    }
    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain)throws IOException,ServletException{
        if(request.getContentLengthLong()>LIMIT){reject(request,response);return;}
        byte[] bytes=request.getInputStream().readNBytes(LIMIT+1);
        if(bytes.length>LIMIT){reject(request,response);return;}
        chain.doFilter(new HttpServletRequestWrapper(request){
            @Override public ServletInputStream getInputStream(){
                var input=new ByteArrayInputStream(bytes);
                return new ServletInputStream(){
                    @Override public int read(){return input.read();}
                    @Override public int read(byte[] b,int off,int length){return input.read(b,off,length);}
                    @Override public boolean isFinished(){return input.available()==0;}
                    @Override public boolean isReady(){return true;}
                    @Override public void setReadListener(ReadListener listener){
                        try{if(isFinished())listener.onAllDataRead();else listener.onDataAvailable();}
                        catch(IOException e){listener.onError(e);}
                    }
                };
            }
            @Override public BufferedReader getReader(){return new BufferedReader(new InputStreamReader(getInputStream(),StandardCharsets.UTF_8));}
        },response);
    }
    private void reject(HttpServletRequest request,HttpServletResponse response)throws IOException{
        response.setStatus(413);response.setContentType("application/json");response.setCharacterEncoding("UTF-8");
        mapper.writeValue(response.getOutputStream(),new ApiErrorResponse(new ApiErrorResponse.ErrorBody("PAYLOAD_TOO_LARGE","请求体超过4MB",List.of(),RequestIdFilter.from(request))));
    }
}
