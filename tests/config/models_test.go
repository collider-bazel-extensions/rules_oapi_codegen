package inventory_test

import (
	"encoding/json"
	"testing"

	"github.com/collider-bazel-extensions/rules_oapi_codegen/tests/config/inventory"
)

// The config file selected models only and named the package; errors.yaml's
// Error is generated into the same package and used by Item.LastError.
func TestModels(t *testing.T) {
	var items []inventory.Item
	if err := json.Unmarshal([]byte(`[{"sku":"a-1","count":3,"lastError":{"message":"low"}}]`), &items); err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Sku != "a-1" || items[0].Count != 3 ||
		items[0].LastError == nil || items[0].LastError.Message != "low" {
		t.Fatalf("items = %+v", items)
	}

	var e inventory.Error
	if err := json.Unmarshal([]byte(`{"message":"boom"}`), &e); err != nil {
		t.Fatal(err)
	}
	if e.Message != "boom" {
		t.Fatalf("error = %+v", e)
	}
}
