# TDP Notifications - Design Documents

This document (and folder) contains information pertinent to the design of the TDP Notification System (aka DEM - Domains External Messaging)

## Table of Contents

- [Overview]
- [System Components]
- [Process Flow Diagram]


## Overview

The TDP Notification system is an asynchronous notification delivery system.
A tenant/client (aka subscriber) declares they wish to "subscribe" to certain notifications by creating a "subscription".  A subscription contains information about the client.  Most importantly specifies:
 - The subscriber's name/tenant id
 - The events that the subscriber wishes to receive notifications for (e.g. DOMAIN.CREATED)
 - The webhook address that will be invoked by the notification system when the above notification type is received
 - An email address that the system will send an email to in the event of a failure to invoke the webhook

(As of this moment - Feb 2025 - only webhook notifications are supported; this will eventually expand to email and possibly SMS notifications)

Once the subscription is created, the system will wait until notifications are received.  When a notification is received (e.g. DOMAIN.CREATED) the system will detect it; it will then look up any subscriptions that match that notification type and then invoke the webhook address that is associated with that subscription.  Hence, this system will notify (via webhook) the subscriber that an event has occurred. 

For a more detailed outline/overview, please see the PDF ("Async Reseller Notifications with TDP") in this folder.

## System Components

At a high level, here are the key components of the system:

Subscription Manager - this is the part of the system that is responsible for CRUD of subscriptions.  This is generally customer facing (e.g a reseller would use the subscription manager to state that they would like to start receiving notifications).  The subscription manager is made up of two core services (APIService and SubscriptionManager) and an RMQ bus to communicate between the two. 

Subscription Database - a Postgres database in the TDP environment. When an event (e.g. DOMAIN.CREATED) happens somewhere in the TDP system, rows are inserted into this database.  That in turn triggers a stored procedure which updates a row (or rows) in a table named `notification_delivery`.  The row(s) will contain the details of any subscriber that is subscribed (such as the webhook address to be invoked) to those notifications

Enqueuer - a service that watches the subscription database - specifically, the `notification_delivery` table.  When it notices a row has been written, takes the content of that row, gathers interesting subscription information related to that row, and then drops it onto a queue ("Webhook Notification Queue"). This is a sign that a notification is ready to be sent out to a subscriber.

Webhook Sender - a service that watches the Webhook Notification Queue for any messages.  Once a message is received, it will examine its payload (e.g. the webhook address specified), create an HMAC signature and then send a POST request to the Webhook, thus completing the notification. If something goes wrong with the POST attempt, retry logic is executed.

Notification Manager - a service that watches the "Final Status Notification Queue" for SUCCESS or FAILED messages, based on the outcome of the Webhook Sender when attempting to send a webhook notification.  Responsible for updating the subscription database with the final status.

## Process Flow And Diagram

In Brief: 
 1. When an interesting event occurs, the `notification_delivery` table (in the Subscription Database) is updated with rows containing details of every subscriber that is subscribed to that notification. 
 2. The Enqueuer notices that row, picks it up, and then places it on the "Webhook Notification Queue". This means that the "WebhookNotificationQueue" has a message containing information about a webhook call that needs to be sent!  Note that this message has a retry-count of 1. The Enqueuer then updates the `notification_delivery` table for the row it detected with a status of PUBLISHING
 3. The Webhook Sender notices the message on the Webhook Notification Queue.  It is picked up and processed (e.g. an HMAC signature is created) - and sends a POST to the webhook address specified in the message. 
    If it succeeds, a "SUCCESS" message is placed on the "Final Status Notification" queue.
    If it fails, retry logic is assessed:
	We examine the rety-count.
		If retry-count is less than 4:
			Increment retry-count and place the message onto RetryQueue<retry-count>
		If retry-count is 4, we assume that the delivery has failed, and we publish a FAILED message onto the "Final Status Notification Queue"
4. The NotificationManager notices the SUCCESS or FAILED message on the "Final Status Notification Queue" and updates the Subscription DB with the appropriate status.  If FAILED, sends an email to the address of the subscriber, informing that the Webhook invocation failed.

This diagram can be seen in this directory.


## Retry Logic

As described above, the WebhookSender will attempt to deliver the message up to 3 times.  The first 3 failures will see the message re-queued on one of the retry queues.
There are 3 retry queues: each is a regular RabbitMQ queue, but with different TTL (time-to-live), but all having the same DLQ (dead letter queue) - which points at the "Webhook Notification Queue".

When the Webhook Sender fails to deliver a message for the first time, it will place the message on RetryQueue 1.  This will have a TTL set to 5 minutes.  This means, that after 5 minutes of sitting on that queue, Rabbit MQ will transfer the message onto its designated Dead Letter Queue - which in fact points to the original "Webhook Notification Queue" - which means that the Webhook Sender will pick it up again for retry.

If the Webhook Sender fails a second time, the message is placed on RetryQueue 2 - which has a TTL set to 1 hour; after that time it will be moved to the DLQ which again points to the Webhook Notification Queue where will be picked up again for a retry.

If the Webhook Sender fails for a third time, the message is placed on RetryQueue 3 - which has a TTL set for 6 hours; again after that time, the message will be moved to the DLQ/Webhook Notification queue for delivery re-attempt. 

On the fourth failure, the system gives up retrying and declares the notification status to be FAILED.  An email should be sent to the subscriber notifying them of the failure.

It's worth noting here that we are just leveraging RabbitMQ configuration to handle the "wait-and-retry" logic of the RetryQueues. 

## Queue Creation
The Webhook Notification/retry queues will be created by the Webhook Sender

## To Be Discussed
Items we have yet to consider:
- Security
- Event retention policy: when an event makes it to the notification_delivery row, how long do we keep it there if it is successful?  How long if it fails?
- How do we handle events that have no subscribers? 
- Monitoring
- Load estimates
- How do we handle email updates (e.g. "We failed to deliver your message"?)
- How do we handle "new" event types?  Is this something we have to configure, or do we allow self service?
- How do we update the notification_delivery table with final SUCCESS/FAILURE?
- Web GUI for subscription management

## Migrating from Lucid
From now on, we are moving from Lucid diagram to diagrams.net to version control our diagrams.
Using Lucid, the process became cumbersome and confising, for any new diagram, we had to duplicate the diagram, then get approvals, and it became messy.
With the new approach, the new diagrams will be inside this project and can be peer reviewed by the team, maintaining single source of truth.

The first step here was to absorb the current latest Lucid diagram and translate it into its draw.io equivalent.
- This was done using draw.io Importer" Chrome extension: https://chromewebstore.google.com/detail/diagramsnet-and-drawio-im/cnoplimhpndhhhnmoigbanpjeghjpohi
- Exported the .drawio file in this directory and export it as an editable svg file, so the PR reviews can be done seemlessly too.
- Updated to the latest flow
- In VSCode, use this extension to edit the drawings: https://marketplace.visualstudio.com/items?itemName=hediet.vscode-drawio
- In GoLand, use this extension to edit the drawings: https://plugins.jetbrains.com/plugin/15635-diagrams-net-integration 


