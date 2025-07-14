# Subscription Notification Processing Flow

```mermaid
flowchart
  NP[Notification Processor] --> DB[[Store notification in database: received]]
  DB --> WH{Webhook Registered?}    
  WH -->|No| DBU3[[Update webhook status: unsupported]]
  DBU3 --> E4([End])
  WH --> |Yes| AD[[Attempt Delivery of Webhook, status: publishing]]
  AD --> DS{Delivery Successful?}
  DS -->|No| AR{Retry Attempts < Max Attempts?}
  DS -->|Yes| DBU[[Update webhook status: published]]
  DBU --> E1([End])
  AR -->|Yes| DBU1[[Update webhook status: failed]]
  DBU1 --> DBU2[[Mark Subscription status: degraded]]
  DBU2 --> SE[[Send Notification Email]]
  AR -->|No| RQ[[Requeue in retry-queue-n]]
  RQ-- retry nth time --->AD
  SE --> E2([End])
```

## Modules Documentation

- [Template](template/README.md): This module defines the database structure for managing templates and their related entities.
