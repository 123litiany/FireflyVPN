package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"unsafe"

	"github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	singtun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/service"
)

const version = "fireflycore/0.1.0 (sing-box 1.13.9)"

// fireflyPlatform 实现 sing-box 的 adapter.PlatformInterface。
// HarmonyOS 的 TUN fd 由 ArkTS 侧 @ohos.net.vpnExtension 创建后传入，
// Go 侧只负责在 OpenInterface 中接管该 fd。
type fireflyPlatform struct {
	tunFd int
}

func (p *fireflyPlatform) Initialize(networkManager adapter.NetworkManager) error {
	return nil
}

func (p *fireflyPlatform) UsePlatformAutoDetectInterfaceControl() bool {
	return false
}

func (p *fireflyPlatform) AutoDetectInterfaceControl(fd int) error {
	return nil
}

func (p *fireflyPlatform) UsePlatformInterface() bool {
	return true
}

func (p *fireflyPlatform) OpenInterface(options *singtun.Options, platformOptions option.TunPlatformOptions) (singtun.Tun, error) {
	options.FileDescriptor = p.tunFd
	options.AutoRoute = false
	return singtun.New(*options)
}

func (p *fireflyPlatform) UsePlatformDefaultInterfaceMonitor() bool {
	return false
}

func (p *fireflyPlatform) CreateDefaultInterfaceMonitor(logger logger.Logger) singtun.DefaultInterfaceMonitor {
	return nil
}

func (p *fireflyPlatform) UsePlatformNetworkInterfaces() bool {
	return false
}

func (p *fireflyPlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) {
	return nil, nil
}

func (p *fireflyPlatform) UnderNetworkExtension() bool {
	return false
}

func (p *fireflyPlatform) NetworkExtensionIncludeAllNetworks() bool {
	return false
}

func (p *fireflyPlatform) ClearDNSCache() {}

func (p *fireflyPlatform) RequestPermissionForWIFIState() error {
	return nil
}

func (p *fireflyPlatform) ReadWIFIState() adapter.WIFIState {
	return adapter.WIFIState{}
}

func (p *fireflyPlatform) SystemCertificates() []string {
	return nil
}

func (p *fireflyPlatform) UsePlatformConnectionOwnerFinder() bool {
	return false
}

func (p *fireflyPlatform) FindConnectionOwner(request *adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return nil, errors.New("connection owner lookup is not supported")
}

func (p *fireflyPlatform) UsePlatformWIFIMonitor() bool {
	return false
}

func (p *fireflyPlatform) UsePlatformNotification() bool {
	return false
}

func (p *fireflyPlatform) SendNotification(notification *adapter.Notification) error {
	return nil
}

var (
	mu       sync.Mutex
	instance *box.Box
)

func startCore(configJSON string, tunFd int) error {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		return errors.New("core already running")
	}
	var options option.Options
	decoder := json.NewDecoder(strings.NewReader(configJSON))
	if err := decoder.Decode(&options); err != nil {
		return err
	}
	platform := &fireflyPlatform{tunFd: tunFd}
	ctx := context.Background()
	ctx = service.ContextWith[adapter.PlatformInterface](ctx, platform)
	boxInstance, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		return err
	}
	if err = boxInstance.Start(); err != nil {
		return err
	}
	instance = boxInstance
	return nil
}

func stopCore() error {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil
	}
	err := instance.Close()
	instance = nil
	return err
}

//export FireflyStart
func FireflyStart(configJSON *C.char, tunFd C.int) *C.char {
	if configJSON == nil {
		return C.CString("config is null")
	}
	if tunFd < 0 {
		return C.CString("invalid tun fd")
	}
	if err := startCore(C.GoString(configJSON), int(tunFd)); err != nil {
		return C.CString(err.Error())
	}
	return C.CString("")
}

//export FireflyStop
func FireflyStop() *C.char {
	if err := stopCore(); err != nil {
		return C.CString(err.Error())
	}
	return C.CString("")
}

//export FireflyVersion
func FireflyVersion() *C.char {
	return C.CString(version)
}

//export FireflyFree
func FireflyFree(value *C.char) {
	if value != nil {
		C.free(unsafe.Pointer(value))
	}
}

func main() {}
