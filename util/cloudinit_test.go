/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package util

import (
	"encoding/base64"
	"testing"
)

func TestPrepareUserData(t *testing.T) {
	input := []byte("#!/bin/bash\necho hello")

	result, err := PrepareUserData(input)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify it's valid base64
	decoded, err := base64.StdEncoding.DecodeString(result)
	if err != nil {
		t.Fatalf("result is not valid base64: %v", err)
	}

	if string(decoded) != string(input) {
		t.Errorf("roundtrip failed: got %q, want %q", string(decoded), string(input))
	}
}

func TestPrepareUserData_Empty(t *testing.T) {
	_, err := PrepareUserData([]byte{})
	if err == nil {
		t.Fatal("expected error for empty bootstrap data, got nil")
	}
}

func TestPrepareUserData_CloudInit(t *testing.T) {
	// Simulate a real cloud-init script
	cloudInit := `#cloud-config
runcmd:
  - curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -
  - systemctl enable rke2-server
  - systemctl start rke2-server
`

	result, err := PrepareUserData([]byte(cloudInit))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Decode and verify
	decoded, err := base64.StdEncoding.DecodeString(result)
	if err != nil {
		t.Fatalf("not valid base64: %v", err)
	}

	if string(decoded) != cloudInit {
		t.Error("cloud-init content not preserved after encode/decode roundtrip")
	}
}
