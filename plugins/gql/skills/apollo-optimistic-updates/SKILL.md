---
name: apollo-optimistic-updates
description: Apollo Client cache updates for mutations. Use when implementing mutations that should update the UI without refetching queries.
---

# Apollo Optimistic Updates

Use `cache.modify` in mutation `update` callbacks instead of `refetchQueries: 'active'` for faster, more efficient UI updates.

## Why avoid refetchQueries

- Triggers network requests for ALL active queries
- Slower UI feedback (waits for server response)
- Unnecessary bandwidth usage
- Can cause loading states to flash

## Pattern: cache.modify

Update specific fields on cached entities directly:

```typescript
const [mutate] = useMutation(MY_MUTATION, {
  onCompleted: () => { /* cleanup */ },
  onError: () => { /* handle error */ },
});

// Pass update in the mutation call to capture current values
mutate({
  variables: { id, newValue },
  update(cache, { data }) {
    if (!data?.myMutation?.success) return;

    cache.modify({
      id: cache.identify({ __typename: 'MyType', id }),
      fields: {
        myField() {
          return newValue;
        },
      },
    });
  },
});
```

## Key points

1. **Pass `update` at call site, not hook config** - closures in hook config capture stale values
2. **Check mutation success** before modifying cache
3. **Use `cache.identify`** to get the cache key for an entity
4. **Include `__typename`** in returned objects for new nested data

## Example: Updating a nested object

```typescript
mutate({
  variables: { caseFileId, isRelevant, reason },
  update(cache, { data }) {
    if (!data?.case?.overrideRelevance?.success) return;

    cache.modify({
      id: cache.identify({ __typename: 'CaseFile', id: caseFileId }),
      fields: {
        relevanceOverride() {
          return {
            __typename: 'RelevanceOverride',
            isRelevant,
            reason,
            createdBy: null, // Server-only field, okay to omit
          };
        },
      },
    });
  },
});
```

## Example: Setting field to null (deletion)

```typescript
mutate({
  variables: { id },
  update(cache, { data }) {
    if (!data?.removeItem?.success) return;

    cache.modify({
      id: cache.identify({ __typename: 'Parent', id: parentId }),
      fields: {
        item() {
          return null;
        },
      },
    });
  },
});
```

## Example: Adding to an array

```typescript
import type { Reference } from '@apollo/client/cache';

mutate({
  variables: { parentId, newItem },
  update(cache, { data }) {
    if (!data?.createItem) return;

    cache.modify({
      id: cache.identify({ __typename: 'Parent', id: parentId }),
      fields: {
        items(existing: readonly Reference[] = []) {
          const newRef = cache.writeFragment({
            data: data.createItem,
            fragment: gql`
              fragment NewItem on Item {
                id
                name
              }
            `,
          });
          return [...existing, newRef];
        },
      },
    });
  },
});
```

## Example: Removing from an array

```typescript
import type { Reference, ModifierDetails } from '@apollo/client/cache';

mutate({
  variables: { itemId },
  update(cache, { data }) {
    if (!data?.removeItem?.success) return;

    cache.modify({
      id: cache.identify({ __typename: 'Parent', id: parentId }),
      fields: {
        items(existing: readonly Reference[] = [], { readField }: ModifierDetails) {
          return existing.filter(
            (ref) => readField('id', ref) !== itemId
          );
        },
      },
    });
  },
});
```

## Combining with local optimistic state

For instant UI feedback before the mutation even starts:

```typescript
const [pendingValue, setPendingValue] = useState<T | null>(null);

// Use pending value for display, fall back to server value
const displayValue = pendingValue ?? serverValue;

const handleMutate = () => {
  setPendingValue(newValue); // Instant UI update

  mutate({
    variables: { newValue },
    update(cache, { data }) {
      // Cache update for other components
    },
    onCompleted: () => setPendingValue(null),
    onError: () => setPendingValue(null),
  });
};
```

## When to use refetchQueries

Still appropriate when:
- Mutation affects many queries in complex ways
- Server computes derived values you need
- Cache structure is too complex to update manually
