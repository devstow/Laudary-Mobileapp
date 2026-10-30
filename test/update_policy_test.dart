// Decision rules of the in-app updater (lib/features/update/update_controller.dart → decideUpdate).
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/features/update/app_release.dart';
import 'package:mobileapp/features/update/resume_point.dart';
import 'package:mobileapp/features/update/update_controller.dart';

AppRelease rel({int code = 2012, bool available = true, bool mandatory = false, String? problem}) => AppRelease.fromJson({
      'applicationId': 'com.cyberstackmedia.smartwash',
      'versionName': '1.0.3',
      'versionCode': code,
      'downloadUrl': 'https://example.test/api/public/app-release/android/file',
      'sizeBytes': 25000000,
      'sha256': 'ABC',
      'certSha256': 'ADE7',
      'minSupportedVersionCode': mandatory ? code : 0,
      'updateAvailable': available,
      'mandatory': mandatory,
      'problem': problem,
      'releaseNotes': 'Automatic updates',
      'releaseNotesAr': 'تحديثات',
    })!;

void main() {
  test('newer optional release is offered; same build is not', () {
    expect(decideUpdate(installedBuild: 2011, release: rel()), UpdateOffer.optional);
    expect(decideUpdate(installedBuild: 2012, release: rel(available: false)), UpdateOffer.none);
    // Defensive: the server said "available" but the build is not newer.
    expect(decideUpdate(installedBuild: 2013, release: rel()), UpdateOffer.none);
  });

  test('mandatory release blocks; postponing an optional one lasts until the next launch only', () {
    expect(decideUpdate(installedBuild: 2009, release: rel(mandatory: true)), UpdateOffer.mandatory);
    expect(decideUpdate(installedBuild: 2011, release: rel(), postponedBuild: 2012), UpdateOffer.none);
    // A newer build than the postponed one is offered again; a mandatory one can never be postponed.
    expect(decideUpdate(installedBuild: 2011, release: rel(code: 2013), postponedBuild: 2012), UpdateOffer.optional);
    expect(decideUpdate(installedBuild: 2011, release: rel(mandatory: true), postponedBuild: 2012), UpdateOffer.mandatory);
  });

  test('a failed check never unlocks a known mandatory update, but does not block otherwise', () {
    expect(decideUpdate(installedBuild: 2011, checkFailed: true), UpdateOffer.none);
    expect(decideUpdate(installedBuild: 2011, checkFailed: true, knownRequiredBuild: 2012), UpdateOffer.mandatoryOffline);
    expect(decideUpdate(installedBuild: 2012, checkFailed: true, knownRequiredBuild: 2012), UpdateOffer.none);
  });

  test('incomplete release metadata is never offered', () {
    expect(decideUpdate(installedBuild: 2011, release: rel(problem: 'no checksum')), UpdateOffer.none);
    expect(AppRelease.fromJson({'versionName': '1'}), isNull);
    expect(rel().sha256, 'abc');
    expect(rel().notesFor('ar'), 'تحديثات');
    expect(rel().notesFor('en'), 'Automatic updates');
  });

  test('resume point keeps ids only and round-trips', () {
    ScreenTracker.reset();
    ScreenTracker.tab = 1;
    ScreenTracker.open('driverTask', 't-1', label: 'ORD-1');
    final p = ResumePoint.fromJson(ScreenTracker.snapshot('u-1').toJson())!;
    expect((p.userId, p.kind, p.id, p.label, p.tab), ('u-1', 'driverTask', 't-1', 'ORD-1', 1));
    ScreenTracker.close('driverTask', 't-1');
    expect(ScreenTracker.snapshot('u-1').kind, 'tab');
    expect(ResumePoint.fromJson('garbage'), isNull);
  });
}
