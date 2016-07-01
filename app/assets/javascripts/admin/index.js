/**
 * Created by eduardo on 25/06/16.
 */
'use strict';

require('./directives/block.js');
require('./controllers');

require('./module').config(function ($stateProvider, $urlRouterProvider) {
    $urlRouterProvider.otherwise('home');
    $urlRouterProvider.when('', '/');

    $stateProvider.state('home', {
        url: '/',
        templateUrl: '/templates/admin/home.html'
    });
    /**
     * Linhas
     */
    $stateProvider.state('lines', {
        url: '/lines',
        abstract: true,
        controller: 'LinesController as ctrl',
        template: '<div ui-view/>'
    });
    $stateProvider.state('lines.index', {
        url: '',
        templateUrl: '/templates/admin/lines-index.html'
    });
    $stateProvider.state('lines.show', {
        url: '/:id',
        templateUrl: '/templates/admin/lines-show.html'
    });
    /**
     * Editor de Rotas
     */
    $stateProvider.state('map', {
        url: '/map',
        controller: 'MapEditorController',
        templateUrl: '/templates/admin/map-editor.html'
    });
});
