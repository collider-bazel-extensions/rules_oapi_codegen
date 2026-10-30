package api_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/oapi-codegen/runtime/types"

	"example.com/consumer/api"
)

func TestHealth(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/healthz" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","checkedAt":"2026-10-30T12:00:00Z","requestId":"6ba7b810-9dad-11d1-80b4-00c04fd430c8"}`))
	}))
	defer srv.Close()

	c, err := api.NewClientWithResponses(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := c.GetHealthWithResponse(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	h := resp.JSON200
	if h == nil || h.Status != api.Ok || h.CheckedAt.Year() != 2026 {
		t.Fatalf("GetHealth = %d %+v", resp.StatusCode(), h)
	}
	var want types.UUID
	if err := want.UnmarshalText([]byte("6ba7b810-9dad-11d1-80b4-00c04fd430c8")); err != nil {
		t.Fatal(err)
	}
	if h.RequestId == nil || *h.RequestId != want {
		t.Fatalf("requestId = %v", h.RequestId)
	}
}
