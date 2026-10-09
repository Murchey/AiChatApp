package com.aichat.server.llm;

import java.util.ArrayList;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix="app.llm")
public class LlmProperties {
    private List<ModelAdapter.ModelDescriptor> models=new ArrayList<>();
    private int timeoutSeconds=45;
    private boolean allowLocalHttp;
    public List<ModelAdapter.ModelDescriptor> getModels(){return models;}
    public void setModels(List<ModelAdapter.ModelDescriptor> models){this.models=models;}
    public int getTimeoutSeconds(){return timeoutSeconds;}
    public void setTimeoutSeconds(int seconds){this.timeoutSeconds=seconds;}
    public boolean isAllowLocalHttp(){return allowLocalHttp;}
    public void setAllowLocalHttp(boolean value){this.allowLocalHttp=value;}
}
