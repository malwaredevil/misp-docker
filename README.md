# Malware Devil MISP Docker
![MISP-DOCKER CI CD](https://github.com/malwaredevil/misp-docker/workflows/MISP-DOCKER%20CI%20CD/badge.svg)
## About

The files in this repository are used to create a Docker container running a [MISP](http://www.misp-project.org) ("Malware Information Sharing Platform") instance. This is a fork of the https://github.com/MISP/misp-docker docker version.

## Significant Changes

Please review the template.env for the new variables

- No optional nginx container. Its easier to set that up separately.
- Uses php 7.4x (Recommended version of PHP from MISP)
- Enables 2 additional modules
  - zip
  - ssdeep
- Installs/Enables GNuPG
- Installs/Enables Plugin settings
  - Enrichment
  - Import
  - Export
- Reduces some of the RED and YELLOW warnings