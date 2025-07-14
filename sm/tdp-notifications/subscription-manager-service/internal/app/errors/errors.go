package smerrors

import "errors"

var ErrNotFound = errors.New("not found")
var ErrInvalidTenantCustomerID = errors.New("invalid tenant customer id")
var ErrStatusCannotBePaused = errors.New("only active or degraded subscription can be paused")
var ErrStatusCannotBeResumed = errors.New("only paused subscription can be resumed")
var ErrInvalidNotificationType = errors.New("invalid notification type")
var ErrInvalidRequest = errors.New("invalid request")
