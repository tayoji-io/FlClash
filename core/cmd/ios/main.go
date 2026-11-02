//go:build ios && cgo

package main

/*
#cgo CFLAGS: -I${SRCDIR}/../..
#include <stdlib.h>
#include "bride.h"
*/
import "C"

import (
	"core"
	"encoding/json"
	"math"
	"runtime/debug"
	"sync"
	"unsafe"
)

func main() {}

func takeCString(s *C.char) string {
	defer C.free_string(s)
	return C.GoString(s)
}

func invokeResult(callback unsafe.Pointer, data string) {
	s := C.CString(data)
	defer C.free(unsafe.Pointer(s))
	C.result(callback, s)
}

func releaseObject(callback unsafe.Pointer) {
	if callback != nil {
		C.release_object(callback)
	}
}

//export invokeMethod
func invokeMethod(callback unsafe.Pointer, paramsChar *C.char) {
	params := takeCString(paramsChar)
	core.InvokeMethod(params, func(data []byte) {
		invokeResult(callback, string(data))
		releaseObject(callback)
	})
}

//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char, mtu C.int) bool {
	defer releaseObject(callback)
	options, _ := json.Marshal(map[string]any{"mtu": int(mtu)})
	return core.StartTun(
		int(fd),
		takeCString(stackChar),
		takeCString(addressChar),
		takeCString(dnsChar),
		string(options),
	)
}

//export quickSetup
func quickSetup(callback unsafe.Pointer, initParamsChar, setupParamsChar *C.char) {
	core.QuickSetup(takeCString(initParamsChar), takeCString(setupParamsChar), func(message string) {
		invokeResult(callback, message)
		releaseObject(callback)
	})
}

var (
	eventListenerLock sync.Mutex
	eventListenerPtr  unsafe.Pointer
)

//export setEventListener
func setEventListener(listener unsafe.Pointer) {
	eventListenerLock.Lock()
	previous := eventListenerPtr
	eventListenerPtr = listener
	eventListenerLock.Unlock()
	if listener == nil {
		core.SetEventListener(nil)
	} else {
		core.SetEventListener(func(data []byte) {
			eventListenerLock.Lock()
			current := eventListenerPtr
			eventListenerLock.Unlock()
			if current != nil {
				invokeResult(current, string(data))
			}
		})
	}
	releaseObject(previous)
}

//export getTotalTraffic
func getTotalTraffic(onlyStatisticsProxy bool) *C.char {
	return C.CString(core.GetTotalTraffic(onlyStatisticsProxy))
}

//export getTraffic
func getTraffic(onlyStatisticsProxy bool) *C.char {
	return C.CString(core.GetTraffic(onlyStatisticsProxy))
}

//export stopTun
func stopTun() {
	core.StopTun()
}

//export suspend
func suspend(_ bool) {}

//export setMemoryLimit
func setMemoryLimit(bytes C.longlong) {
	if bytes <= 0 {
		debug.SetMemoryLimit(math.MaxInt64)
		return
	}
	debug.SetMemoryLimit(int64(bytes))
}

//export forceGC
func forceGC() {
	core.ForceGC()
}

//export updateDns
func updateDns(s *C.char) {
	core.UpdateDns(takeCString(s))
}
