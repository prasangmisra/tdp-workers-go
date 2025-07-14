# Workers registry error messages/codes
## Used status codes
- 1000: Success
- 1001: Pending
- 2102: Unimplemented option
- 2302: Object exists
- 2303: Object does not exist
- 2202: Invalid auth info
- 2301: Not pending transfer


## Usage
### Workers
#### All workers
- if 1000 -> completed else fail

#### Domain workers
- domain provision 1001 -> completed_conditionally
- domain renew 1001 -> completed_conditionally
- domain transfer action if not 1000 -> failed
- domain transfer in if not 1001 -> warn
- domain update 1001 -> completed_conditionally
- domain update 2102 -> failed
- domain update 2302 -> failed (with message host association already exists)
- domain delete 1001 -> (in redemption grace period)
- domain Claims Check if not 1000 -> failed
- domain info transfer check if not 1000 -> failed
- domain info transfer check 2202 -> failed (invalid auth info)

#### Host workers
- host delete 2303 -> completed (Object exists)
- host provision 2302 -> completed (Object does not exist)

### Cron workers
- domain transfer in (transfer query) 1000 -> process success response
- domain transfer in (transfer query) 2301 -> process pending response
