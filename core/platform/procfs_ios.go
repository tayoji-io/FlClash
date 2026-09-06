//go:build ios

package platform

import "net"

func QuerySocketUidFromProcFs(_, _ net.Addr) int {
	return -1
}
