package petstore_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	openapi_types "github.com/oapi-codegen/runtime/types"

	"github.com/collider-bazel-extensions/rules_oapi_codegen/tests/petstore"
)

// The generated client round-trips against an httptest server: path params,
// JSON request bodies, typed 200/404/201 responses, and the `format: date`
// runtime type.
func TestClient(t *testing.T) {
	born := openapi_types.Date{Time: time.Date(2020, 5, 17, 0, 0, 0, 0, time.UTC)}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /pets/{petId}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.PathValue("petId") != "42" {
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(map[string]string{"message": "no pet " + r.PathValue("petId")})
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"id": 42, "name": "Rex", "born": "2020-05-17"})
	})
	mux.HandleFunc("POST /pets", func(w http.ResponseWriter, r *http.Request) {
		var in map[string]any
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		in["id"] = 7
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(in)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	c, err := petstore.NewClientWithResponses(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()

	got, err := c.GetPetWithResponse(ctx, 42)
	if err != nil {
		t.Fatal(err)
	}
	if got.JSON200 == nil || got.JSON200.Id != 42 || got.JSON200.Name != "Rex" || got.JSON200.Born != born {
		t.Fatalf("GetPet(42) = %d %+v", got.StatusCode(), got.JSON200)
	}

	missing, err := c.GetPetWithResponse(ctx, 1)
	if err != nil {
		t.Fatal(err)
	}
	if missing.JSON404 == nil || missing.JSON404.Message != "no pet 1" {
		t.Fatalf("GetPet(1) = %d %+v", missing.StatusCode(), missing.JSON404)
	}

	tag := "good"
	created, err := c.CreatePetWithResponse(ctx, petstore.CreatePetJSONRequestBody{Name: "Fido", Tag: &tag, Born: born})
	if err != nil {
		t.Fatal(err)
	}
	if created.JSON201 == nil || created.JSON201.Id != 7 || created.JSON201.Name != "Fido" || *created.JSON201.Tag != "good" {
		t.Fatalf("CreatePet = %d %+v", created.StatusCode(), created.JSON201)
	}
}
