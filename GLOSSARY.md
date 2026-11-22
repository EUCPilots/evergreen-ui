# Evergreen Workbench

A Windows desktop application and PowerShell module (`EvergreenUI`) for discovering, downloading, packaging and publishing applications resolved by the Evergreen module.

## Language

**Definition**:
An `App.json` file describing one application: how to resolve its latest installer, how to install it and how to detect it.
_Avoid_: Manifest, package definition, template

**Artifact**:
A resolved installer for a specific version of an application, produced by evaluating a Definition's filter or a Shell App definition's source.
_Avoid_: Download, installer, result

**Library**:
The local folder tree of Artifacts maintained by Evergreen's library update.
_Avoid_: Repository, cache, store

**Package**:
A deployable container built from an Artifact: an `.intunewin` file for Intune or a `.zip` for Nerdio.
_Avoid_: Bundle, build output

**Provider**:
A destination that Artifacts or Packages are published to: Intune, Nerdio or Microsoft 365 Apps.
_Avoid_: Target, platform, service

**Shell App definition**:
A description of a Nerdio application and its detection, installation and uninstallation scripts.
_Avoid_: App.json Definition, Intune Definition

**Shell App**:
An application managed in Nerdio Manager, with one or more installer versions.
_Avoid_: Intune app, Package

**Shell App version pruning**:
Removal of older Shell App versions while retaining a selected number of versions.
_Avoid_: Version cleanup, version purge

**Publish**:
Upload an Artifact or Package and its metadata to a Provider. Replaces the v1 term "Import".
_Avoid_: Import, deploy, push

**Intune update app**:
An Intune app that delivers an update as required to all devices, rather than
using the Definition's assignments.
_Avoid_: Supersedence, ordinary app

**Supersedence**:
An Intune relationship in which a new app replaces a previous app.
_Avoid_: Update app, assignment

**Job**:
A cancellable background operation that reports progress and log output, such as a download, library update or publish.
_Avoid_: Task, worker, operation

**Headless layer**:
The public cmdlets that perform all Workbench functionality without any WPF dependency. The UI only calls these.
_Avoid_: Backend, core, engine
