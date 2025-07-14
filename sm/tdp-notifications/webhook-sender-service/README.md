# Webhook Sender Service

The **webhook-sender-service** is responsible for processing webhook notifications from RabbitMQ. It listens to messages from the `webhook_notification` queue, attempts to send them to the designated webhook URL, and handles retries if necessary.

## Queue Configuration

| Queue Name             | Purpose                                          |
|------------------------|--------------------------------------------------|
| `webhook_notification` | Main queue where webhook requests are published. |
| `webhook_notification_retry_1`         | First retry queue (5m delay).                    |
| `webhook_notification_retry_2`         | Second retry queue (1h delay).                   |
| `webhook_notification_retry_3`         | Final retry queue (6h delay).                    |

- If a webhook request fails, it is moved to a retry queue based on the `x_retry` count, which we get from the header of the message.
- Messages in retry queues have a **TTL** (Time-To-Live). Once expired, they are sent back to the **`webhook_notification`** queue for reprocessing.
- If `x_retry` exceeds **3**, the message is discarded.
