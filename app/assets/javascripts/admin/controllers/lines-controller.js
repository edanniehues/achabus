/**
 * Created by eduardo on 29/06/16.
 */
'use strict';
class LinesController {
    constructor($state, $http, $scope, $rootScope, $mdToast, $mdDialog, $q) {
        /**
         * Serviços
         */
        this.$http = $http;
        this.$scope = $scope;
        this.$state = $state;
        this.$mdToast = $mdToast;
        this.$mdDialog = $mdDialog;
        this.$q = $q;

        /**
         * Estado
         */
        this.lines = [];
        this.line = null;
        this.newRoute = null;
        this.filters = '';
        this.query = {
            limit: 15,
            page: 1
        };

        /**
         * Buga buga ES5!!!
         * @type {LinesController}
         */
        const self = this;
        /**
         * Detectando que estado estamos
         */
        $rootScope.$on('$stateChangeStart', (event, state, params) => {
            this.checkState(state, params);
        });

        /**
         * Paginação da tabela. Isso tem que ficar aqui por questões de o md-data-table ser tanso
         *
         * @param page
         * @param limit
         * @returns {*}
         */
        this.$scope.getLines = function(page = 1, limit = 15) {
            let def = $q.defer();
            $http.get('/lines.json', {params: {filter: self.filters, page: page, size: limit}}).then(data => {
                def.resolve(data.data.content);
                self.lines = data.data;
            }, a => def.reject(a));
            return def.promise;
        };

        this.checkState($state.current, $state.params);

        $scope.$watch('ctrl.filters', () => this.$scope.getLines(1, 15));
    }

    /**
     * Helper para as transições de estado
     * 
     * @param state
     * @param params
     */
    checkState(state, params) {
        switch(state.name) {
            case "lines.index":
                this.loadLines();
                break;
            case "lines.show":
                this.loadLine(params.id);
                break;
        }
    }

    /**
     *
     * LISTA DE LINHAS
     *
     */
    loadLines() {
        this.$scope.setTitle('Linhas');
        this.filters = '';
        this.query.limit = 15;
        this.query.page = 1;
        this.$scope.getLines();
    }

    /**
     *
     * VISUALIZAR LINHA
     *
     */

    /**
     * Carrega a linha a partir do $http.
     *
     * @param id id da linha
     */
    loadLine(id) {
        this.$http.get('/lines/' + id + '.json').then(data => {
            this.line = data.data;
            this.newRoute = {
                line_id: this.line.id
            };
            this.$scope.setTitle(this.line.identifier + ' - ' + this.line.name);
        });
    }

    /**
     * Abre a popup de criação de rota.
     * 
     * @param event evento originador
     */
    createRoute(event) {
        var route = {
            line_id: this.line.id
        };
        this.$mdDialog.show({
            templateUrl: '/templates/admin/route-form-popup.html',
            controller: 'RoutePopupController as ctrl',
            targetEvent: event,
            locals: {
                line: this.line,
                route: route
            }
        }).then(() => this.loadLine(this.line.id));
    }

    /**
     * Abre a popup de edição de rota para a rota selecionada.
     * 
     * @param route a rota
     * @param event evento originador
     */
    editRoute(route, event) {
        route = {
            line_id: this.line.id,
            origin: route.origin,
            destination: route.destination,
            observation: route.observation
        };
        this.$mdDialog.show({
            templateUrl: '/templates/admin/route-form-popup.html',
            controller: 'RoutePopupController as ctrl',
            targetEvent: event,
            locals: {
                line: this.line,
                route: route
            }
        }).then(() => this.loadLine(this.line.id));
    }
    
    deleteRoute(id) {
        if(confirm('Excluir rota?')) {
            this.$http.delete('/routes/' + id + '.json').then(() => {
                this.$mdToast.showSimple('Rota excluída com sucesso.');
                loadLine(this.line.id);
            });
        }
    }

    /**
     *
     * POPUPS
     *
     */

    /**
     * Abre a popup de edição de linha.
     *
     * @param id id da linha
     * @param event evento originador
     */
    openEditLine(id, event) {
        this.$http.get(`/lines/${id}.json`).then(data => {
            let line = {
                id: data.data.id,
                identifier: data.data.identifier,
                name: data.data.name,
                path: data.data.path ? data.data.path.join(', ') : '',
                line_group_id: data.data.line_group_id,
                itinerary_link: data.data.itinerary_link,
                timetable_link: data.data.timetable_link
            };
            this.$mdDialog.show({
                templateUrl: '/templates/admin/line-form-popup.html',
                controller: 'LinePopupController as ctrl',
                targetEvent: event,
                locals: {
                    line: line
                }
            }).then(() => {
                if(this.$state.current.name == 'lines.show') {
                    this.loadLine(id);
                } else {
                    this.loadLines();
                }
            });
        });
    }

    openNewLine(event) {
        let line = {
            id: null,
            identifier: '',
            name: '',
            path: '',
            line_group_id: null,
            itinerary_link: '',
            timetable_link: ''
        };
        this.$mdDialog.show({
            templateUrl: '/templates/admin/line-form-popup.html',
            controller: 'LinePopupController as ctrl',
            targetEvent: event,
            locals: {
                line: line
            }
        }).then(() => {
            this.loadLines();
        });
    }
}

module.exports = LinesController;