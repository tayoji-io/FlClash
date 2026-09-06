//go:build ios && cgo

package main

import (
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/log"
)

func handleUpdateDns(value string) {
	go func() {
		log.Infoln("[DNS] updateDns %s", value)
		resolver.ClearCache()
		resolver.ResetConnection()
	}()
}
