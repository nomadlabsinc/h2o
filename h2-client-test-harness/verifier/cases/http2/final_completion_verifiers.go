package http2

import (
	"github.com/nomadlabsinc/h2-client-test-harness/verifier"
)

func init() {
	// Final 13 completion test verifiers
	verifier.Register("complete/1", testComplete1)
	verifier.Register("complete/2", testComplete2)
	verifier.Register("complete/3", testComplete3)
	verifier.Register("complete/4", testComplete4)
	verifier.Register("complete/5", testComplete5)
	verifier.Register("complete/6", testComplete6)
	verifier.Register("complete/7", testComplete7)
	verifier.Register("complete/8", testComplete8)
	verifier.Register("complete/9", testComplete9)
	verifier.Register("complete/10", testComplete10)
	verifier.Register("complete/11", testComplete11)
	verifier.Register("complete/12", testComplete12)
	verifier.Register("complete/13", testComplete13)
}

// All completion tests expect successful operation
func testComplete1() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete2() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete3() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete4() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete5() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete6() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete7() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete8() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete9() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete10() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete11() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete12() error {
	return verifier.ExpectSuccessfulRequest()
}

func testComplete13() error {
	return verifier.ExpectSuccessfulRequest()
}