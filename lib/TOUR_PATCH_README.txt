MERQ POS Guided Tour Patch — Categories-first update

What changed in this patch:
- Categories screen has a two-step tour. Step 1 spotlights the real Add category button.
- The tour advances only after the category form reports a successful save and the provider finishes saving it.
- Step 2 explains how to select the saved category when creating a product, and warns that Uncategorized products may be hidden from Register.
- Register blocks starting product creation when no categories exist and explains how to add one first.
- Register Guided tour also gives the category-first instructions when there are no categories, instead of starting a product tutorial that cannot be completed correctly.
- No new package dependencies.

Apply: back up the current lib folder, merge the lib folder from this ZIP into the project, then run flutter pub get, flutter analyze, and test on device.

Validation note: Flutter analyze/build was not run in this environment. Test the category save failure path and the Settings -> Categories -> Add category flow before release.
