# Subscription Manager

Subscription manager service is listening to RabbitMQ queue and calls handlers according to received message type.

Queue Name: **subscriptionmanager**

| Handler                       | Message Type                                           |
|-------------------------------|--------------------------------------------------------|
| CreateSubscriptionHandler     | tucows.message.datamanager.SubscriptionCreateRequest   |
| UpdateSubscriptionHandler     | tucows.message.datamanager.SubscriptionUpdateRequest   |
| GetSubscriptionByIDHandler    | tucows.message.datamanager.SubscriptionGetRequest      |
| ListSubscriptionsHandler      | tucows.message.datamanager.SubscriptionListRequest     |
| DeleteSubscriptionByIDHandler | tucows.message.datamanager.SubscriptionDeleteRequest   |
| PauseSubscriptionHandler      | tucows.message.datamanager.SubscriptionPauseRequest    |
| ResumeSubscriptionHandler     | tucows.message.datamanager.SubscriptionResumeRequest   |

