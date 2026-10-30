package petserver

import (
	"context"
	"sync"
	"time"

	openapi_types "github.com/oapi-codegen/runtime/types"
)

// Store implements the generated StrictServerInterface with an in-memory map.
type Store struct {
	mu   sync.Mutex
	next int64
	pets map[int64]Pet
}

func NewStore() *Store {
	born := openapi_types.Date{Time: time.Date(2020, 5, 17, 0, 0, 0, 0, time.UTC)}
	return &Store{next: 43, pets: map[int64]Pet{42: {Id: 42, Name: "Rex", Born: born}}}
}

func (s *Store) GetPet(_ context.Context, req GetPetRequestObject) (GetPetResponseObject, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if p, ok := s.pets[req.PetId]; ok {
		return GetPet200JSONResponse(p), nil
	}
	return GetPet404JSONResponse{Message: "no such pet"}, nil
}

func (s *Store) CreatePet(_ context.Context, req CreatePetRequestObject) (CreatePetResponseObject, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	p := Pet{Id: s.next, Name: req.Body.Name, Tag: req.Body.Tag, Born: req.Body.Born}
	s.pets[p.Id] = p
	s.next++
	return CreatePet201JSONResponse(p), nil
}
