//go:build android && cgo

package main

import (
	"strings"

	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/log"
)

func handleUpdateDns(value string) {
	go func() {
		log.Infoln("[DNS] updateDns %s", value)
		dns.UpdateSystemDNS(strings.Split(value, ","))
		dns.FlushCacheWithDefaultResolver()
	}()
}
