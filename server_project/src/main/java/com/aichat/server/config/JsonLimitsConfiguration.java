package com.aichat.server.config;

import com.fasterxml.jackson.core.StreamReadConstraints;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class JsonLimitsConfiguration {
    @Bean Jackson2ObjectMapperBuilderCustomizer jsonReadLimits(){
        return builder->builder.postConfigurer(mapper->mapper.getFactory().setStreamReadConstraints(
            StreamReadConstraints.builder().maxNestingDepth(64).maxStringLength(3*1024*1024).maxNumberLength(128).build()));
    }
}
