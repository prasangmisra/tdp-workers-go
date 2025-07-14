# TDP notifications api-service

The `api-service` provides the RESP API to manage subscriptions. It exposes the following endpoints:

| Endpoint Description      | HTTP Verb | URL                               | Status      |
|---------------------------|-----------|-----------------------------------|-------------|
| Default                   | GET       | /                                 | Complete    |
| Health Check              | GET       | /health                           | Complete    |
| Create Subscription       | POST      | /api/subscriptions                | Complete    |
| Delete Subscription by ID | DELETE    | /api/subscriptions/{id}           | Complete    |
| Get Subscription by ID    | GET       | /api/subscriptions/{id}           | Complete    |
| Get All Subscriptions     | GET       | /api/subscriptions                | Complete    |
| Update Subscription       | PATCH     | /api/subscriptions/{id}           | Complete    |
| Pause Subscription        | PATCH     | /api/subscriptions/{id}           | Complete    |
| Resume Subscription       | PATCH     | /api/subscriptions/{id}           | Complete    |
| Create Notification       | POST      | /api/notifications                 | wip         |

## OpenAPI documentation
The domain api documentation can be access at:
- [Local](http://localhost:8190/swagger/index.html)

The OpenAPI specification is automatically generated using the `swaggo/swag` package. After adding or updating the documentation please run the following command:
```shell
make swagger
```