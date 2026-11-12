package com.futurebuild.wealthtree.model;


import java.time.LocalDate;

/** An outgoing payment (positive amount = money spent). */
public record Transaction(LocalDate date, SpendingCategory category, double amount, String description) implements java.io.Serializable {}
