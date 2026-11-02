//go:build ios

package core

import (
	"encoding/json"
	"sync"
	"sync/atomic"

	"core/tun"

	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
)

var (
	iosEventListenerLock sync.RWMutex
	iosEventListener     func([]byte)
	iosListening         atomic.Bool

	iosTunLock    sync.Mutex
	iosTunHandler *sing_tun.Listener
)

func StartTun(fd int, stack, address, dns, options string) bool {
	iosTunLock.Lock()
	defer iosTunLock.Unlock()
	stopTunLocked()
	if fd == 0 {
		logError("startTun was handed no tun descriptor")
		return false
	}
	listener := tun.Start(fd, stack, address, dns, options)
	if listener == nil {
		return false
	}
	log.Infoln("TUN address: %v", listener.Address())
	iosTunHandler = listener
	if !isRunning.Load() {
		handleStartListener()
	} else {
		handleResetConnections()
		bumpRouteEpoch()
	}
	return true
}

func StopTun() {
	iosTunLock.Lock()
	stopTunLocked()
	iosTunLock.Unlock()
	if isRunning.Load() {
		handleStopListener()
	}
}

func stopTunLocked() {
	if iosTunHandler == nil {
		return
	}
	_ = iosTunHandler.Close()
	iosTunHandler = nil
}

func InvokeMethod(data string, reply func([]byte)) {
	call := &MethodCall{}
	if err := json.Unmarshal([]byte(data), call); err != nil {
		reply(encodeResponse(MethodResponse{Error: &MethodError{
			Code:    "invalid_method_call",
			Message: err.Error(),
		}}))
		return
	}
	dispatchMethodCall(call, reply)
}

func QuickSetup(initParamsString, setupParamsString string, answer func(string)) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				logError("panic in quickSetup: %v\n%s", r, stackTrace())
				answer("internal panic")
			}
		}()
		initParams := InitParams{}
		if err := json.Unmarshal([]byte(initParamsString), &initParams); err != nil {
			answer("init failed")
			return
		}
		if !handleInitClash(&initParams) {
			answer("init failed")
			return
		}
		setupParams := &SetupParams{}
		if err := json.Unmarshal([]byte(setupParamsString), setupParams); err != nil {
			answer(err.Error())
			return
		}
		if err := handleSetupConfig(setupParams); err != nil {
			answer(err.Error())
			return
		}
		answer("")
	}()
}

func SetEventListener(listener func([]byte)) {
	iosEventListenerLock.Lock()
	iosEventListener = listener
	iosListening.Store(listener != nil)
	iosEventListenerLock.Unlock()
	if listener == nil {
		stopRouteWatch()
	}
}

func hasEventListener() bool {
	return iosListening.Load()
}

func deliverEvent(data []byte) {
	iosEventListenerLock.RLock()
	defer iosEventListenerLock.RUnlock()
	if iosEventListener == nil {
		return
	}
	iosEventListener(data)
}

func GetTraffic(onlyStatisticsProxy bool) string {
	return marshalResult(handleGetTraffic(onlyStatisticsProxy))
}

func GetTotalTraffic(onlyStatisticsProxy bool) string {
	return marshalResult(handleGetTotalTraffic(onlyStatisticsProxy))
}

func ForceGC() {
	handleForceGC()
}

func UpdateDns(value string) {
	go func() {
		log.Infoln("[DNS] updateDns %s", value)
		resolver.ClearCache()
		resolver.ResetConnection()
	}()
}

func ResetNetwork() {
	go handleResetNetwork()
}

func marshalResult(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		logError("Result marshal error: %v", err)
		return ""
	}
	return string(data)
}

func init() {
	registerMethod(updateDnsMethod, withArguments(func(value string) bool {
		UpdateDns(value)
		return true
	}))
}
