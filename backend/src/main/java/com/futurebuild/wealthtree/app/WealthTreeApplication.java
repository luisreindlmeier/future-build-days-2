package com.futurebuild.wealthtree.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.futurebuild.wealthtree")
public class WealthTreeApplication {
    public static void main(String[] args) {
        java.util.Locale.setDefault(java.util.Locale.ENGLISH);   // "€5,500" and "1.6 months" on every laptop
        SpringApplication.run(WealthTreeApplication.class, args);
    }
}
