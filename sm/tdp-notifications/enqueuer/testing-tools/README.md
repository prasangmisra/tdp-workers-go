Manual tools for running quick tests.  These are useful for testing the enqueuer

There are two tools here:

- `create_queue` - This will create the webhook notification queue as defined in the config file
- `create_test_notification` - This will create a test subscription in the SudDB (if one does not already exist) and then create a notification (also in the SubDB) which that subscription is listening for. 

If you are running in an environment "from scratch" (e.g. just the enqueuer), you will need to run `create_queue` first.   After that, you can run create_test_notification (a few times, if desired) to create a set of notifications.

At this point, running the enqueuer's _main_ program will detect those notifications and place them on the RabbitMQ bus!
