# Malware Devil MISP Docker

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

## TODO
- [ ] Update Documentation to include how to to use nginx as reverse proxy if desired (USE THIS AS GUIDE: https://www.freecodecamp.org/news/docker-nginx-letsencrypt-easy-secure-reverse-proxy-40165ba3aee2/).

## TOWANT
- [ ] Automate nginx deployment model.