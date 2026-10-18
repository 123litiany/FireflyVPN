package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"unsafe"

	"github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singtun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/control"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/common/x/list"
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
	if p.tunFd < 0 {
		return nil, errors.New("no tun fd provided (self-test config must not contain a tun inbound)")
	}
	options.FileDescriptor = p.tunFd
	options.AutoRoute = false
	return singtun.New(*options)
}

func (p *fireflyPlatform) UsePlatformDefaultInterfaceMonitor() bool {
	return true
}

// 默认接口监控：sing-box 在存在 PlatformInterface 时必定调用
// CreateDefaultInterfaceMonitor 并注册回调，返回 nil 会导致空指针崩溃。
type fireflyInterfaceMonitor struct {
	access      sync.Mutex
	callbacks   list.List[singtun.DefaultInterfaceUpdateCallback]
	current     atomic.Pointer[control.Interface]
	myInterface string
}

func discoverDefaultInterface() *control.Interface {
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		if strings.HasPrefix(iface.Name, "tun") {
			continue
		}
		return &control.Interface{
			Index:        iface.Index,
			MTU:          iface.MTU,
			Name:         iface.Name,
			HardwareAddr: iface.HardwareAddr,
			Flags:        iface.Flags,
		}
	}
	return nil
}

func (m *fireflyInterfaceMonitor) Start() error {
	iface := discoverDefaultInterface()
	if iface != nil {
		m.current.Store(iface)
		m.emit(iface, 0)
	}
	return nil
}

func (m *fireflyInterfaceMonitor) Close() error {
	return nil
}

func (m *fireflyInterfaceMonitor) DefaultInterface() *control.Interface {
	return m.current.Load()
}

func (m *fireflyInterfaceMonitor) OverrideAndroidVPN() bool {
	return false
}

func (m *fireflyInterfaceMonitor) AndroidVPNEnabled() bool {
	return false
}

func (m *fireflyInterfaceMonitor) RegisterCallback(callback singtun.DefaultInterfaceUpdateCallback) *list.Element[singtun.DefaultInterfaceUpdateCallback] {
	m.access.Lock()
	defer m.access.Unlock()
	return m.callbacks.PushBack(callback)
}

func (m *fireflyInterfaceMonitor) UnregisterCallback(element *list.Element[singtun.DefaultInterfaceUpdateCallback]) {
	if element == nil {
		return
	}
	m.access.Lock()
	defer m.access.Unlock()
	m.callbacks.Remove(element)
}

func (m *fireflyInterfaceMonitor) RegisterMyInterface(interfaceName string) {
	m.access.Lock()
	defer m.access.Unlock()
	m.myInterface = interfaceName
}

func (m *fireflyInterfaceMonitor) MyInterface() string {
	m.access.Lock()
	defer m.access.Unlock()
	return m.myInterface
}

func (m *fireflyInterfaceMonitor) emit(defaultInterface *control.Interface, flags int) {
	m.access.Lock()
	callbacks := m.callbacks.Array()
	m.access.Unlock()
	for _, callback := range callbacks {
		callback(defaultInterface, flags)
	}
}

func (p *fireflyPlatform) CreateDefaultInterfaceMonitor(logger logger.Logger) singtun.DefaultInterfaceMonitor {
	return &fireflyInterfaceMonitor{}
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
	// include.Context 注册全部入站/出站/端点/DNS/服务实现
	ctx = include.Context(ctx)
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
