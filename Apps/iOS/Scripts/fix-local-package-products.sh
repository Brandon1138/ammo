#!/usr/bin/env bash
set -euo pipefail

project_file="Ammo.xcodeproj/project.pbxproj"

package_id="$(
  awk '
    /\/\* Begin XCLocalSwiftPackageReference section \*\// { in_section = 1 }
    /\/\* End XCLocalSwiftPackageReference section \*\// { in_section = 0 }
    in_section && /\/\* XCLocalSwiftPackageReference "\.\.\/\.\." \*\// { candidate = $1 }
    in_section && /relativePath = \.\.\/\.\.;/ && candidate { print candidate; exit }
  ' "$project_file"
)"

if [[ -z "$package_id" ]]; then
  echo "Unable to find local Swift package reference for ../.." >&2
  exit 1
fi

USAGEKIT_PACKAGE_ID="$package_id" perl -0pi -e '
  my $package_id = $ENV{"USAGEKIT_PACKAGE_ID"};
  s/(\t\t[0-9A-F]+ \/\* UsageKit \*\/ = \{\n\t\t\tisa = XCSwiftPackageProductDependency;\n)(?!\t\t\tpackage = )/${1}\t\t\tpackage = $package_id;\n/g;
' "$project_file"
