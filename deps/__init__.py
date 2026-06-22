# Simulated, instrumented, fault-injectable dependency tier for Contoso Commerce Cloud.
# db / cache / queue are in-process Python — NOT real infra — but each emits genuine
# OpenTelemetry CLIENT (dependency) spans, so the Application Map and KQL correlation are real.
