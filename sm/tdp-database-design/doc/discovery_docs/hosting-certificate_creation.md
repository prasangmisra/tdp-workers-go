```mermaid

sequenceDiagram
    Hosting Api->>+Order Manager: Provision Hosting Request
    Order Manager->>+Database: Insert Provision Hosting Order
    Order Manager-->>-Hosting Api: Hosting Order Recieved Response
    Database->>+Provision Hosting Certificate Worker: Provision Hosting Certificate Job
    Provision Hosting Certificate Worker->>+Certbot: Certificate Create Request
    Certbot-->>-Provision Hosting Certificate Worker: Acknowledge Certificate Request
    Certbot-->>+Provision Hosting Certificate Update Worker: Certificate Creation Successful
    Provision Hosting Certificate Update Worker->>+Database: Update Provision Hosting Certificate Job
    Database->>+Provision Hosting Worker: Provision Hosting Job
    Provision Hosting Worker->>+Hosting Platform: Provision New Hosting
    Hosting Platform->>+Provision Hosting Update Worker: Hosting Creation Successful
    Provision Hosting Update Worker->>+Database: Update Provision Hosting Job

```