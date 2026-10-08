package com.aichat.server.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app")
public class AppProperties {
    private String serverVersion = "0.1.0-m0";
    private String apiVersion = "v1";
    private String minClientVersion = "1.6.0";
    private String publicBaseUrl = "";
    private boolean inviteRequired = true;
    private final Features features = new Features();
    private final Security security = new Security();

    public String getServerVersion() { return serverVersion; }
    public void setServerVersion(String serverVersion) { this.serverVersion = serverVersion; }
    public String getApiVersion() { return apiVersion; }
    public void setApiVersion(String apiVersion) { this.apiVersion = apiVersion; }
    public String getMinClientVersion() { return minClientVersion; }
    public void setMinClientVersion(String minClientVersion) { this.minClientVersion = minClientVersion; }
    public String getPublicBaseUrl() { return publicBaseUrl; }
    public void setPublicBaseUrl(String publicBaseUrl) { this.publicBaseUrl = publicBaseUrl; }
    public boolean isInviteRequired() { return inviteRequired; }
    public void setInviteRequired(boolean inviteRequired) { this.inviteRequired = inviteRequired; }
    public Features getFeatures() { return features; }
    public Security getSecurity() { return security; }

    public static class Features {
        private boolean sync;
        private boolean stories = true;
        private boolean comments;
        private boolean adminPublish = true;
        private boolean llmRelay;

        public boolean isSync() { return sync; }
        public void setSync(boolean sync) { this.sync = sync; }
        public boolean isStories() { return stories; }
        public void setStories(boolean stories) { this.stories = stories; }
        public boolean isComments() { return comments; }
        public void setComments(boolean comments) { this.comments = comments; }
        public boolean isAdminPublish() { return adminPublish; }
        public void setAdminPublish(boolean adminPublish) { this.adminPublish = adminPublish; }
        public boolean isLlmRelay() { return llmRelay; }
        public void setLlmRelay(boolean llmRelay) { this.llmRelay = llmRelay; }
    }

    public static class Security {
        private String tokenPepper = "";
        private boolean requireTokenPepper;
        private String bootstrapAdminToken = "";
        private int accessTokenMinutes = 15;
        private int refreshTokenDays = 30;

        public String getTokenPepper() { return tokenPepper; }
        public void setTokenPepper(String tokenPepper) { this.tokenPepper = tokenPepper; }
        public boolean isRequireTokenPepper() { return requireTokenPepper; }
        public void setRequireTokenPepper(boolean requireTokenPepper) { this.requireTokenPepper = requireTokenPepper; }
        public String getBootstrapAdminToken() { return bootstrapAdminToken; }
        public void setBootstrapAdminToken(String bootstrapAdminToken) { this.bootstrapAdminToken = bootstrapAdminToken; }
        public int getAccessTokenMinutes() { return accessTokenMinutes; }
        public void setAccessTokenMinutes(int accessTokenMinutes) { this.accessTokenMinutes = accessTokenMinutes; }
        public int getRefreshTokenDays() { return refreshTokenDays; }
        public void setRefreshTokenDays(int refreshTokenDays) { this.refreshTokenDays = refreshTokenDays; }
    }
}
