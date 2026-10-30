package petserver_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	openapi_types "github.com/oapi-codegen/runtime/types"

	"github.com/collider-bazel-extensions/rules_oapi_codegen/tests/petstore"
	"github.com/collider-bazel-extensions/rules_oapi_codegen/tests/server/petserver"
)

// A strict net/http server and a client, both generated from the same spec,
// talk to each other. The embedded spec (`generate = [..., "spec"]`) loads.
func TestServerAndClient(t *testing.T) {
	h := petserver.HandlerFromMux(
		petserver.NewStrictHandler(petserver.NewStore(), nil),
		http.NewServeMux(),
	)
	srv := httptest.NewServer(h)
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
	if got.JSON200 == nil || got.JSON200.Name != "Rex" {
		t.Fatalf("GetPet(42) = %d %+v", got.StatusCode(), got.JSON200)
	}

	born := openapi_types.Date{Time: time.Date(2024, 1, 2, 0, 0, 0, 0, time.UTC)}
	created, err := c.CreatePetWithResponse(ctx, petstore.CreatePetJSONRequestBody{Name: "Fido", Born: born})
	if err != nil {
		t.Fatal(err)
	}
	if created.JSON201 == nil || created.JSON201.Id != 43 || created.JSON201.Born != born {
		t.Fatalf("CreatePet = %d %+v", created.StatusCode(), created.JSON201)
	}

	missing, err := c.GetPetWithResponse(ctx, 7)
	if err != nil {
		t.Fatal(err)
	}
	if missing.StatusCode() != http.StatusNotFound || missing.JSON404 == nil {
		t.Fatalf("GetPet(7) = %d %+v", missing.StatusCode(), missing.JSON404)
	}

	spec, err := petserver.GetSwagger()
	if err != nil {
		t.Fatal(err)
	}
	if spec.Info.Title != "Petstore" {
		t.Fatalf("embedded spec title = %q", spec.Info.Title)
	}
}
