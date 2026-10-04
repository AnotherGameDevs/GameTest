# Collection journal, camp shelf and sets

* **Journal** (`J` or the JOURNAL button, top right): one card per treasure type (11), real 3D model (silhouette until
  discovered), name, rarity, home layer, "Found xN - worth $", set tracker per layer, "PUT ON SHELF" for discovered entries.
* **Home layer / sets** (`CollectionSpec`): the layer where a treasure is most common (ties go shallower).
  Soil: Old Coin, Pottery Shard. Clay: Bronze Ring, Clay Figurine. Stone: Fossil Fragment, Ancient Necklace.
  Ruins: Cut Gemstone, Ruin Tablet, Fossil Claw*, Golden Scarab*, Sun Pharaoh Mask*.   (*carry-home artifacts)
* **Recording rules** (server, the only writer is `CollectionSpec.Register`):
  * ordinary finds register when legitimately awarded into the backpack (`LootService.Award`, not when the pack is full);
  * important artifacts register **only after a successful deposit** (`ArtifactService.Deposit`); finding, carrying,
    placing or dying never unlocks an entry;
  * duplicates only increase the count; they still pay through selling/depositing.
* **Set completion:** completing the last member of a layer set sends `SetCompleted` once; the client shows a "SET COMPLETE"
  popup + sound. Totals and per-layer progress are in the journal header.
* **Camp shelf** (`CampShelf`, `Config.Collection`): 4 slots, chosen in the journal (`SetDisplay`, validated against the saved
  collection, never silently replaces a full shelf). Built **only on the local client** from the local player's own saved
  `Display` list, with a sign "<name>'s SHELF - only you see this", at `Config.Collection.ShelfPosition`
  (west side of camp, facing the arrival area, footprint registered in `Config.Camp.Footprints.Shelf` and checked by the
  layout test). Other players' shelves are never shown to you and yours is never shown to them.
* **Saving:** `Collection`, `Display` and hint progress `Guide` are in the profile (schema v3, `DataMigrations`).
* Not included (by request): a second currency, museum building.
