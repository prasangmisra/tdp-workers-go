# Email Sender Service

The **email-sender-service** is responsible for processing email notifications from RabbitMQ. 
It listens to messages from the `email_send_queue` queue, converts them into RFC 822-style email message with appropriate headers 
and attempts to send them via smtp server. It handles retries if necessary based on configuration.

## Debugging the Email Sender Service (Through Visual Studio Code)
1. Edit config/dev.yaml
    - Under the RMQ section:
        - set the `hostname` to `localhost`
        - set the `port` to 5672
        - set `tlsenabled` to false
2. Start RabbitMQ
    - From inside VSCode, open tdp-notifications/build/docker-compose.yml
    - Locate the `rabbitmq` section, and on the line above it - click "Run Service"
3. Set your breakpoints as necessary
4. Start the Email Sender Service in debug mode from VSCosde:
    - Hit Ctrl-Shift-D -- this should cause a pop-up to appear in the top left corner of VSCode
    - In the drop-down, select "Launch Email Sender Service" and click the green triangle
    - In the lower window, click the Debug Console tab it is it not already open; this will let you "watch" the service start, 
and all log messages will go here.  The service will now start in debug mode!
5. Once running, to "trigger" the service, you'll need to stick a message on the queue that the service listens to.  
The easiest way to do this is to run the `create-test-message` program.  See `testing-tools/create-test-message/create-test-message.go` 
for details on how to do this! 

## Local testing
In order to use Google smtp server for local testing, you need to create the new `App password` in your Google account. 
Use the generated password as `smtpserver.password` and your email address as `smtpserver.username` in the [config](configs/dev.yaml) file.

It is recommended to remove created `App password` after testing is completed.
