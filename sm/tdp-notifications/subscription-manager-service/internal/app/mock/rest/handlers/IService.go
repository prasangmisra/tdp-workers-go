// Code generated by mockery v2.51.1. DO NOT EDIT.

package handlersmock

import (
	context "context"

	mock "github.com/stretchr/testify/mock"
	subscription "github.com/tucowsinc/tdp-messages-go/message/subscription"
)

// IService is an autogenerated mock type for the IService type
type IService struct {
	mock.Mock
}

// CreateSubscription provides a mock function with given fields: _a0, _a1
func (_m *IService) CreateSubscription(_a0 context.Context, _a1 *subscription.SubscriptionCreateRequest) (*subscription.SubscriptionCreateResponse, error) {
	ret := _m.Called(_a0, _a1)

	if len(ret) == 0 {
		panic("no return value specified for CreateSubscription")
	}

	var r0 *subscription.SubscriptionCreateResponse
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionCreateRequest) (*subscription.SubscriptionCreateResponse, error)); ok {
		return rf(_a0, _a1)
	}
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionCreateRequest) *subscription.SubscriptionCreateResponse); ok {
		r0 = rf(_a0, _a1)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*subscription.SubscriptionCreateResponse)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, *subscription.SubscriptionCreateRequest) error); ok {
		r1 = rf(_a0, _a1)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// DeleteSubscriptionByID provides a mock function with given fields: _a0, _a1
func (_m *IService) DeleteSubscriptionByID(_a0 context.Context, _a1 *subscription.SubscriptionDeleteRequest) (*subscription.SubscriptionDeleteResponse, error) {
	ret := _m.Called(_a0, _a1)

	if len(ret) == 0 {
		panic("no return value specified for DeleteSubscriptionByID")
	}

	var r0 *subscription.SubscriptionDeleteResponse
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionDeleteRequest) (*subscription.SubscriptionDeleteResponse, error)); ok {
		return rf(_a0, _a1)
	}
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionDeleteRequest) *subscription.SubscriptionDeleteResponse); ok {
		r0 = rf(_a0, _a1)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*subscription.SubscriptionDeleteResponse)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, *subscription.SubscriptionDeleteRequest) error); ok {
		r1 = rf(_a0, _a1)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// GetSubscriptionByID provides a mock function with given fields: _a0, _a1
func (_m *IService) GetSubscriptionByID(_a0 context.Context, _a1 *subscription.SubscriptionGetRequest) (*subscription.SubscriptionGetResponse, error) {
	ret := _m.Called(_a0, _a1)

	if len(ret) == 0 {
		panic("no return value specified for GetSubscriptionByID")
	}

	var r0 *subscription.SubscriptionGetResponse
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionGetRequest) (*subscription.SubscriptionGetResponse, error)); ok {
		return rf(_a0, _a1)
	}
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionGetRequest) *subscription.SubscriptionGetResponse); ok {
		r0 = rf(_a0, _a1)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*subscription.SubscriptionGetResponse)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, *subscription.SubscriptionGetRequest) error); ok {
		r1 = rf(_a0, _a1)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// ListSubscriptions provides a mock function with given fields: _a0, _a1
func (_m *IService) ListSubscriptions(_a0 context.Context, _a1 *subscription.SubscriptionListRequest) (*subscription.SubscriptionListResponse, error) {
	ret := _m.Called(_a0, _a1)

	if len(ret) == 0 {
		panic("no return value specified for ListSubscriptions")
	}

	var r0 *subscription.SubscriptionListResponse
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionListRequest) (*subscription.SubscriptionListResponse, error)); ok {
		return rf(_a0, _a1)
	}
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionListRequest) *subscription.SubscriptionListResponse); ok {
		r0 = rf(_a0, _a1)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*subscription.SubscriptionListResponse)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, *subscription.SubscriptionListRequest) error); ok {
		r1 = rf(_a0, _a1)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// PauseSubscription provides a mock function with given fields: _a0, _a1
func (_m *IService) PauseSubscription(_a0 context.Context, _a1 *subscription.SubscriptionPauseRequest) (*subscription.SubscriptionPauseResponse, error) {
	ret := _m.Called(_a0, _a1)

	if len(ret) == 0 {
		panic("no return value specified for PauseSubscription")
	}

	var r0 *subscription.SubscriptionPauseResponse
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionPauseRequest) (*subscription.SubscriptionPauseResponse, error)); ok {
		return rf(_a0, _a1)
	}
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionPauseRequest) *subscription.SubscriptionPauseResponse); ok {
		r0 = rf(_a0, _a1)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*subscription.SubscriptionPauseResponse)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, *subscription.SubscriptionPauseRequest) error); ok {
		r1 = rf(_a0, _a1)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// ResumeSubscription provides a mock function with given fields: _a0, _a1
func (_m *IService) ResumeSubscription(_a0 context.Context, _a1 *subscription.SubscriptionResumeRequest) (*subscription.SubscriptionResumeResponse, error) {
	ret := _m.Called(_a0, _a1)

	if len(ret) == 0 {
		panic("no return value specified for ResumeSubscription")
	}

	var r0 *subscription.SubscriptionResumeResponse
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionResumeRequest) (*subscription.SubscriptionResumeResponse, error)); ok {
		return rf(_a0, _a1)
	}
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionResumeRequest) *subscription.SubscriptionResumeResponse); ok {
		r0 = rf(_a0, _a1)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*subscription.SubscriptionResumeResponse)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, *subscription.SubscriptionResumeRequest) error); ok {
		r1 = rf(_a0, _a1)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// UpdateSubscription provides a mock function with given fields: _a0, _a1
func (_m *IService) UpdateSubscription(_a0 context.Context, _a1 *subscription.SubscriptionUpdateRequest) (*subscription.SubscriptionUpdateResponse, error) {
	ret := _m.Called(_a0, _a1)

	if len(ret) == 0 {
		panic("no return value specified for UpdateSubscription")
	}

	var r0 *subscription.SubscriptionUpdateResponse
	var r1 error
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionUpdateRequest) (*subscription.SubscriptionUpdateResponse, error)); ok {
		return rf(_a0, _a1)
	}
	if rf, ok := ret.Get(0).(func(context.Context, *subscription.SubscriptionUpdateRequest) *subscription.SubscriptionUpdateResponse); ok {
		r0 = rf(_a0, _a1)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*subscription.SubscriptionUpdateResponse)
		}
	}

	if rf, ok := ret.Get(1).(func(context.Context, *subscription.SubscriptionUpdateRequest) error); ok {
		r1 = rf(_a0, _a1)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// NewIService creates a new instance of IService. It also registers a testing interface on the mock and a cleanup function to assert the mocks expectations.
// The first argument is typically a *testing.T value.
func NewIService(t interface {
	mock.TestingT
	Cleanup(func())
}) *IService {
	mock := &IService{}
	mock.Mock.Test(t)

	t.Cleanup(func() { mock.AssertExpectations(t) })

	return mock
}
