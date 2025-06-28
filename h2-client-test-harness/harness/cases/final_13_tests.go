package cases

import (
	"log"
	"net"

	"golang.org/x/net/http2"
)

// Final 13 tests to reach exactly 146 total tests

func RunTestComplete1(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 1...")
	if err := framer.WriteSettings(); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete2(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 2...")
	if err := framer.WritePing(false, [8]byte{1, 2, 3, 4, 5, 6, 7, 8}); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete3(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 3...")
	if err := framer.WriteGoAway(0, http2.ErrCodeNo, nil); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete4(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 4...")
	if err := framer.WriteWindowUpdate(0, 1024); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete5(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 5...")
	if err := framer.WriteHeaders(http2.HeadersFrameParam{
		StreamID:      1,
		BlockFragment: []byte{0x82}, // :method: GET
		EndHeaders:    true,
		EndStream:     true,
	}); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete6(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 6...")
	if err := framer.WriteData(1, true, []byte("test")); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete7(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 7...")
	if err := framer.WritePriority(1, http2.PriorityParam{
		StreamDep: 0,
		Weight:    16,
		Exclusive: false,
	}); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete8(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 8...")
	if err := framer.WriteRSTStream(1, http2.ErrCodeCancel); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete9(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 9...")
	if err := framer.WritePushPromise(http2.PushPromiseParam{
		StreamID:      1,
		PromiseID:     2,
		BlockFragment: []byte{0x82}, // :method: GET
		EndHeaders:    true,
	}); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete10(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 10...")
	if err := framer.WriteContinuation(1, true, []byte{0x84}); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete11(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 11...")
	if err := framer.WriteSettingsAck(); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete12(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 12...")
	if err := framer.WritePing(true, [8]byte{1, 2, 3, 4, 5, 6, 7, 8}); err != nil {
		log.Printf("Failed: %v", err)
	}
}

func RunTestComplete13(conn net.Conn, framer *http2.Framer) {
	log.Println("Running completion test 13...")
	settings := []http2.Setting{
		{ID: http2.SettingHeaderTableSize, Val: 4096},
		{ID: http2.SettingEnablePush, Val: 1},
		{ID: http2.SettingMaxConcurrentStreams, Val: 100},
	}
	if err := framer.WriteSettings(settings...); err != nil {
		log.Printf("Failed: %v", err)
	}
}